---
name: update-framework
description: Upgrade the aws-data-platform-framework pinned in this domain. Clones the framework repo to a temp dir, reads release notes AND diffs the public interface (Terraform variables/outputs + datalake_sdk Python API) between the current and target version to surface breaking changes, patches the `?ref=` pins, proposes edits on user code, then runs `terraform init -upgrade && terraform plan` to verify.
---

# update-framework

Upgrade the framework version this domain depends on.

Invocation: `/update-framework [vX.Y.Z]`. If the version is omitted, use the latest release.

Framework repo (public): `https://github.com/erwan-simon/aws-data-platform-framework`.

## What can break when the framework moves

- **Terraform interface** of `domain_factory` and `pipeline_factory`: variables (new required, removed, tightened validation), outputs, the `tasks_configuration` object schema.
- **Python SDK** (`datalake_sdk`) used by tasks at runtime: the `def main(job)` contract, methods on the `job` object (`job.ingest`, `job.spark_session`, …), the `ProcessingResponse` return type, anything imported from `datalake_sdk`. The SDK ships in the wheel republished by `domain_factory`, so a framework bump = a possible SDK API change too.

Both surfaces must be diffed.

## Procedure

0. **Working tree must be clean.** Run `git status --porcelain`. If the output is non-empty, **stop immediately** and tell the user to commit (or stash) before re-running the skill. Rationale: this skill edits both `iac/*.tf` and `iac/<pipeline>/*/code/main.py`; mixing those edits with unrelated in-flight changes makes the bump impossible to review or revert cleanly. Do not offer to `git stash` on behalf of the user — let them decide.

1. **Resolve current version.** Grep `?ref=` in `iac/domain.tf` and `iac/pipeline.tf`. They must agree — if not, stop and report. Save as `CURRENT`.

2. **Clone the framework** into a temp dir:
   ```
   FW_DIR=$(mktemp -d)
   git clone --quiet https://github.com/erwan-simon/aws-data-platform-framework "$FW_DIR"
   ```
   All subsequent diffs / release notes run inside `$FW_DIR`.

3. **Resolve target version.** If the user passed a version, use it. Otherwise: `git -C "$FW_DIR" tag --sort=-v:refname | head -n1`. Save as `TARGET`. If `CURRENT == TARGET`, stop: already up to date.

4. **Release notes** for context (the "why"). Tags between CURRENT (exclusive) and TARGET (inclusive):
   ```
   git -C "$FW_DIR" log --tags --simplify-by-decoration --pretty=format:'%d' <CURRENT>..<TARGET>
   ```
   For each tag in that range, read the annotated tag message (`git -C "$FW_DIR" tag -l --format='%(contents)' <tag>`) and the changelog if present (`CHANGELOG.md` at that ref). Summarize briefly.

5. **Diff the Terraform interface** — source of truth for IaC contract:
   ```
   git -C "$FW_DIR" diff <CURRENT>..<TARGET> -- \
     domain_factory/variables.tf domain_factory/outputs.tf \
     pipeline_factory/variables.tf pipeline_factory/outputs.tf \
     'pipeline_factory/modules/*/variables.tf' 'pipeline_factory/modules/*/outputs.tf'
   ```

6. **Diff the SDK public surface** — source of truth for Python contract:
   ```
   git -C "$FW_DIR" diff <CURRENT>..<TARGET> -- 'datalake_sdk/datalake_sdk/*.py'
   ```
   Focus on signatures and return types in `base_processing_wrapper.py`, `native_python_processing_wrapper.py`, `spark_processing_wrapper.py`, `ingestion.py`, and anything exported at the package top level. Implementation-only changes (private helpers) don't matter for user code.

7. **Classify every change** from the diffs into two buckets:

   **(A) Mandatory** — needed just to keep the current pipeline working after the bump:
   - *Terraform*: variables newly required (no default), variables removed, validation tightened, outputs renamed/removed, changes to the `tasks_configuration` object schema.
   - *Python SDK*: changed signature of `main(job)` or its expected return type, methods removed/renamed on `job`, changes to `ProcessingResponse` fields, renamed/removed imports from `datalake_sdk`.

   **(B) Optional new capabilities** — features the framework now offers that the user could adopt but doesn't have to:
   - New optional variables on `domain_factory` / `pipeline_factory` (added *with* a default).
   - New keys in the `tasks_configuration` schema with a default.
   - New methods on `job` / new SDK helpers / new ingestion modes.
   - New top-level resources or behaviors enabled by a new flag (e.g. an `enable_*` switch defaulting to false).
   - New trigger types, new task types, new outputs.

   If both buckets are empty, say so explicitly and skip to step 10 (still bump the pin so future `terraform init` pulls the new ref).

8. **Submit a plan and wait for approval.** Before touching any file, present the user with a single structured plan:

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

   Plus: bump `?ref=<CURRENT>` → `?ref=<TARGET>` in iac/domain.tf and iac/pipeline.tf.
   ```

   For each item in bucket (B), ask the user explicitly: *"The framework now supports X, which lets you do Y with benefit Z. Adopting it would mean modifying <files>. Want it in?"* Record each yes/no.

   Do not edit anything until the user has signed off on the plan as a whole.

9. **Apply.**
   - Patch the version pin (`?ref=` in `iac/domain.tf`, `iac/pipeline.tf`; plus `dataplatform_version` if it exists as a local/variable).
   - Apply every bucket-(A) edit.
   - Apply each bucket-(B) edit the user accepted.
   - Skip every bucket-(B) edit the user declined.

10. **Verify.**
    ```
    terraform -chdir=iac init -upgrade
    terraform -chdir=iac plan
    ```
    Summarize: resource churn, errors, unexpected destroy/replace. Map any error back to a bucket-(A) finding and propose a fix. The SDK side cannot be validated locally — flag explicitly that runtime-only failures (a renamed `job.x` method) only surface at task execution time, so the user should sanity-check each `<pipeline>/*/code/main.py` after the bump.

11. **Clean up.** `rm -rf "$FW_DIR"`.

## Guardrails

- Never silence a plan error by removing arguments blindly — map every error to a documented interface change first.
- If the clone fails (no network), stop and report — without the diff this skill has no added value over a manual sed.
- Don't commit the version bump — leave changes staged for review.
