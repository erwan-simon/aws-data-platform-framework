---
name: new-pipeline
description: Scaffold a new Step Functions pipeline alongside the existing ones in this domain. Creates `iac/pipeline_<name>.tf` (module call to pipeline_factory) and `iac/<name>/` (task code + orchestration template), interactively asks for trigger type and starter tasks, and submits the full plan before editing.
---

# new-pipeline

Scaffold a new pipeline in this domain.

Invocation: `/new-pipeline [name]`. If the name is omitted, ask for it.

## Layout convention

Every pipeline owns a folder named after itself under `iac/`:

```
iac/
├── pipeline_<name>.tf                       # module "pipeline_<name>" calling pipeline_factory
└── <name>/
    ├── orchestration_configuration.tftpl.json
    └── <task_name>/
        ├── code/main.py  (or main.sql)
        └── requirements.txt
```

The `.tf` stays at `iac/` root (Terraform doesn't recurse into subfolders). The orchestration template and all task code live under `iac/<name>/`.

## Procedure

0. **Working tree must be clean.** Run `git status --porcelain`. If non-empty, stop and tell the user to commit/stash first. Do not stash on their behalf.

1. **Collect inputs.** Ask the user (one batch of questions):
   - **Pipeline name** (snake_case). Must not collide with an existing `module "pipeline_<name>"` or folder `iac/<name>/`. Reject names like `pipeline_tasks`, reserved Terraform keywords, anything not matching `^[a-z][a-z0-9_]*$`.
   - **Trigger type**: `schedule` (cron string), `eventbridge` (pattern), or `manual` (no trigger).
   - **Starter content**: empty skeleton (just the module + an empty orchestration JSON), or one placeholder Python task to validate the chain end-to-end.
   - **Copy from an existing pipeline?** If yes, list the sibling pipelines in `iac/` and ask which to clone — copies its `tasks_configuration` shape and orchestration JSON, then renames as needed.

2. **Submit a plan.** Before any edit, present the user with:
   ```
   New pipeline: <name>
   Trigger:      <type> (<argument>)
   Starter:      <empty | placeholder task | copied from <other>>

   Files to create:
     - iac/pipeline_<name>.tf
     - iac/<name>/orchestration_configuration.tftpl.json
     - iac/<name>/<task>/code/main.py  (if placeholder)
     - iac/<name>/<task>/requirements.txt  (if placeholder)
   ```
   Wait for explicit approval before writing anything.

3. **Generate files.**

   **`iac/pipeline_<name>.tf`** — `module "pipeline_<name>"` calling `pipeline_factory` with the same `source` as the existing `iac/pipeline.tf` (read it to copy the `?ref=` exactly — never hardcode a version). Set `pipeline_name = "<name>"`, `domain_object = module.domain`, the chosen `trigger`, an empty `tasks_configuration = {}` (or populated if a starter task was chosen), and `orchestration_configuration_template_file_path = "${path.root}/<name>/orchestration_configuration.tftpl.json"`. Pass `role_to_assume_arn = var.role_to_assume_arn`.

   **`iac/<name>/orchestration_configuration.tftpl.json`** — Step Functions definition. If empty pipeline, generate a minimal `{ "Comment": "...", "StartAt": "noop", "States": { "noop": { "Type": "Pass", "End": true } } }` and warn the user to replace it before deploying. If a starter task is included, wire it as the single state with `End: true`, using the `${___TASK_NAME_UPPER___CONFIGURATION___}` placeholder pattern (see existing pipeline for the convention).

   **`iac/<name>/<task>/code/main.py`** + **`requirements.txt`** (only if starter task): minimal `def main(job):` returning an empty dict, with a TODO comment pointing to `iac/.terraform/modules/domain/docs/pipelines.md` for the task contract.

4. **Report next steps.** Tell the user:
   - Replace the orchestration template + `tasks_configuration` with their actual flow.
   - Run `cd iac && terraform init && terraform plan` to validate the new module wiring (no `apply` triggered by the skill).
   - Don't commit yet — let the user review.

## Guardrails

- Never overwrite an existing `iac/pipeline_<name>.tf` or `iac/<name>/` — abort with a clear message if they exist.
- Match the framework version pin (`?ref=`) on the new module to the one on the existing `iac/pipeline.tf`. Mismatched pins in the same project break `terraform init`.
- Don't run `terraform apply` automatically. The user will iterate on tasks before deploying.
- Don't commit. Leave the new files staged-or-unstaged for review.
