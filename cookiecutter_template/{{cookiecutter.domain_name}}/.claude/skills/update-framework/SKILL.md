---
name: update-framework
description: Upgrade the aws-data-platform-framework pinned in this domain. Clones the framework repo to a fixed temp dir, reads release notes AND diffs the public interface (Terraform variables/outputs + datalake_sdk Python API + task runtime base image) between the current and target version to surface breaking changes, patches the `?ref=` pins, proposes edits on user code, then runs `terraform init -upgrade` followed by `terraform plan` to verify.
---

# update-framework

Upgrade the framework version this domain depends on.

Invocation: `/update-framework [vX.Y.Z]`. If the version is omitted, use the latest release.

Framework repo (public): `https://github.com/erwan-simon/aws-data-platform-framework`.

## What can break when the framework moves

- **Terraform interface** of `domain_factory` and `pipeline_factory`: variables (new required, removed, tightened validation), outputs, the `tasks_configuration` object schema.
- **Python SDK** (`datalake_sdk`) used by tasks at runtime: the `def main(job)` contract, methods on the `job` object (`job.ingest`, `job.spark_session`, …), the `ProcessingResponse` return type, anything imported from `datalake_sdk`. The SDK ships in the wheel republished by `domain_factory`, so a framework bump = a possible SDK API change too.
- **Task runtime base image** — in particular the Python version baked into the image the framework uses to run user tasks. A bump that moves the task runtime Python (e.g. 3.13 → 3.11) silently breaks every `pip install` of user packages on CodeArtifact whose `requires-python` excludes the new version (the user's `code/shared_lib/pyproject.toml` and tasks' `requirements.txt`). This drift does not show up in `variables.tf` / `outputs.tf` diffs — it's hidden in the framework's task Dockerfile.
- **Automatic new resources** from `domain_factory` / `pipeline_factory` that ship as default-enabled and appear as CREATEs on the next `terraform plan` (failsafe-lambda SNS topic, ECR self-healing, docker-validation precondition, etc.). The user can neither accept nor decline these — they just happen — but they must be surfaced at scoping time so the plan output isn't a surprise.
- **CI template drift** pulled by the user's `.gitlab-ci.yml` (e.g. `devops-platform-ci-templates`). Not strictly the framework, but framework releases typically expect a matching CI template version. Worth flagging during scoping.

All five surfaces must be diffed.

## Read-only contract on the framework clone

The clone at `/tmp/aws-data-platform-framework` is **read-only**. Never edit, never `git commit`, never `git push` against it. This skill only reads from that directory. If you need to test changes against the framework itself, that's a separate workflow done in the framework repo, not here.

## Procedure

0. **Working tree must be clean.** Run `git status --porcelain`. If the output is non-empty, **stop immediately** and tell the user to commit (or stash) before re-running the skill. Rationale: this skill edits both `iac/*.tf` and `iac/<pipeline>/*/code/main.py`; mixing those edits with unrelated in-flight changes makes the bump impossible to review or revert cleanly. Do not offer to `git stash` on behalf of the user — let them decide.

1. **Resolve current version.** Grep `?ref=` in `iac/domain.tf` and `iac/pipeline.tf`. They must agree — if not, stop and report. Save as `CURRENT`.

2. **Clone the framework into a fixed path** so every `Bash(...)` call is cleanly allowlistable (`$(...)` / `$(mktemp -d)` make the static permission matcher fail and force a manual approval per call). Use:
   ```
   git clone --quiet https://github.com/erwan-simon/aws-data-platform-framework /tmp/aws-data-platform-framework
   ```
   If the directory already exists from a previous run, `cd /tmp/aws-data-platform-framework && git fetch --tags --quiet` instead of re-cloning (two separate `Bash` calls, never chained with `&&`). Re-emphasize the **read-only contract** above to yourself before doing anything in that directory.

3. **Resolve and normalize target version.** If the user passed a version, normalize it: strip leading `V` → `v` (tags are lowercase), trim whitespace. If the normalized form still doesn't match any tag, stop and tell the user what tags exist. Otherwise: `git -C /tmp/aws-data-platform-framework tag --sort=-v:refname` and take the first line. Save as `TARGET`. If `CURRENT == TARGET`, stop: already up to date.

4. **Release notes** for context (the "why"). Tags between CURRENT (exclusive) and TARGET (inclusive):
   ```
   git -C /tmp/aws-data-platform-framework log --tags --simplify-by-decoration --pretty=format:'%d' <CURRENT>..<TARGET>
   ```
   For each tag in that range, read the annotated tag message:
   ```
   git -C /tmp/aws-data-platform-framework tag -l --format='%(contents)' <tag>
   ```
   and the changelog if present (`CHANGELOG.md` at that ref). Summarize briefly. Each `git` call goes in its own `Bash` invocation — do not chain.

5. **Diff the Terraform interface** — source of truth for IaC contract:
   ```
   git -C /tmp/aws-data-platform-framework diff <CURRENT>..<TARGET> -- \
     domain_factory/variables.tf domain_factory/outputs.tf \
     pipeline_factory/variables.tf pipeline_factory/outputs.tf \
     'pipeline_factory/modules/*/variables.tf' 'pipeline_factory/modules/*/outputs.tf'
   ```

   Also diff the factory bodies themselves (not just the public interface) so automatic-new-resources show up:
   ```
   git -C /tmp/aws-data-platform-framework diff <CURRENT>..<TARGET> -- \
     'domain_factory/*.tf' 'pipeline_factory/*.tf'
   ```

6. **Diff the SDK public surface** — source of truth for Python contract:
   ```
   git -C /tmp/aws-data-platform-framework diff <CURRENT>..<TARGET> -- 'datalake_sdk/datalake_sdk/*.py'
   ```
   Focus on signatures and return types in `base_processing_wrapper.py`, `native_python_processing_wrapper.py`, `spark_processing_wrapper.py`, `ingestion.py`, and anything exported at the package top level. Implementation-only changes (private helpers) don't matter for user code.

7. **Diff the task runtime base image** — source of truth for runtime Python version:
   ```
   git -C /tmp/aws-data-platform-framework diff <CURRENT>..<TARGET> -- \
     'pipeline_factory/modules/*/Dockerfile*' \
     'pipeline_factory/modules/build_and_upload_image_to_ecr/*'
   ```
   Look for `FROM python:X.Y` / `ARG PYTHON_VERSION` / `BASE_IMAGE_URI` changes. If the Python minor version drifts, plan to scan user code in step 8.

8. **Scan user packages for `requires-python` mismatch** (only when step 7 surfaced a Python drift, otherwise skip). Read every `code/*/pyproject.toml` and `iac/<pipeline>/*/requirements.txt`. For each package the user publishes locally (typically `code/shared_lib`), check the `python = "^X.Y"` constraint in its `pyproject.toml` against the framework's new task runtime Python. Mismatch = a mandatory edit in step 10 (relax the constraint and bump the version so the rebuild triggers; the existing `iac/shared_lib.tf` regex picks up the new version automatically).

9. **Classify every change** from the diffs into three buckets:

   **(A) Mandatory** — needed just to keep the current pipeline working after the bump:
   - *Terraform*: variables newly required (no default), variables removed, validation tightened, outputs renamed/removed, changes to the `tasks_configuration` object schema.
   - *Python SDK*: changed signature of `main(job)` or its expected return type, methods removed/renamed on `job`, changes to `ProcessingResponse` fields, renamed/removed imports from `datalake_sdk`.
   - *Runtime Python drift*: every `requires-python` mismatch found at step 8.

   **(B) Optional new capabilities** — features the framework now offers that the user could adopt but doesn't have to:
   - New optional variables on `domain_factory` / `pipeline_factory` (added *with* a default).
   - New keys in the `tasks_configuration` schema with a default.
   - New methods on `job` / new SDK helpers / new ingestion modes.
   - New top-level resources or behaviors enabled by a new flag (e.g. an `enable_*` switch defaulting to false).
   - New trigger types, new task types, new outputs.

   **(C) Automatic behavior changes** — changes the user can neither accept nor decline; they just happen. Surface them so the user isn't surprised by the plan output:
   - New default-enabled resources (failsafe-lambda alarm SNS topic, ECR self-healing, docker preconditions, EMR pre-start hooks, …).
   - Changed default values on existing optional variables that materially alter behavior.
   - New required-by-default lifecycle hooks (preconditions, replace-triggered-by, etc.).

   If all three buckets are empty, say so explicitly and skip to step 11 (still bump the pin so future `terraform init` pulls the new ref).

10. **Submit a plan and wait for approval.** Before touching any file, present the user with a single structured plan:

    ```
    Framework <CURRENT> → <TARGET>

    Mandatory changes (must apply or the pipeline breaks):
      1. <one-line description> — affects <file:lines> — proposed edit: <diff sketch>
      2. ...

    New features available (opt-in — ask one by one):
      A. <feature name>
         What it does: <one sentence>
         Value: <why a user would adopt it>
         Cost to adopt: <files to touch, rough effort>
      B. ...

    Automatic behavior changes (FYI — no user choice):
      α. <description> — shows up as <plan output kind> on first apply.
      β. ...

    Plus: bump `?ref=<CURRENT>` → `?ref=<TARGET>` in iac/domain.tf and iac/pipeline.tf.
    ```

    For each item in bucket (B), ask the user explicitly: *"The framework now supports X, which lets you do Y with benefit Z. Adopting it would mean modifying <files>. Want it in?"* Record each yes/no.

    Do not edit anything until the user has signed off on the plan as a whole.

11. **Apply.**
    - Patch the version pin (`?ref=` in `iac/domain.tf`, `iac/pipeline.tf`; plus `dataplatform_version` if it exists as a local/variable).
    - Apply every bucket-(A) edit (including runtime-Python `requires-python` relaxations from step 8 — bump the user-package version one patch so the framework rebuilds).
    - Apply each bucket-(B) edit the user accepted.
    - Skip every bucket-(B) edit the user declined.
    - Bucket (C) requires no code change — it's informational.

12. **Verify.** Run these as **two separate `Bash` calls**, never chained with `&&` (the chain isn't statically allowlistable and forces a manual approval each time):
    ```
    terraform -chdir=iac init -upgrade
    ```
    then
    ```
    terraform -chdir=iac plan
    ```
    Summarize: resource churn (split between bucket-(A) consequences and bucket-(C) automatic creates), errors, unexpected destroy/replace. Map any error back to a bucket-(A) finding and propose a fix. The SDK side cannot be validated locally — flag explicitly that runtime-only failures (a renamed `job.x` method) only surface at task execution time, so the user should sanity-check each `<pipeline>/*/code/main.py` after the bump.

13. **Clean up.**
    ```
    rm -rf /tmp/aws-data-platform-framework
    ```
    Pre-authorize this pattern globally (`Bash(rm -rf /tmp/aws-data-platform-framework)`) so it doesn't prompt. The fixed path makes the cleanup cleanly allowlistable; a `$(...)`-resolved path is not.

## Guardrails

- Never silence a plan error by removing arguments blindly — map every error to a documented interface change first.
- If the clone fails (no network), stop and report — without the diff this skill has no added value over a manual sed.
- Don't commit the version bump — leave changes staged for review.
- The clone at `/tmp/aws-data-platform-framework` is **read-only**. Never edit, never push, never run any write-back command against it.
