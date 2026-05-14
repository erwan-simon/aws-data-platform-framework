# CLAUDE.md — {{cookiecutter.domain_name}}

Domain on the [AWS Data Platform Framework](https://github.com/erwan-simon/aws-data-platform-framework).

## Layout
- `iac/domain.tf` — provisions the domain (S3, Glue DB, IAM, Lake Formation, …)
- `iac/pipeline.tf` — declares the Step Functions pipeline; `tasks_configuration` is the canonical list of tasks
- `iac/<pipeline_name>/orchestration_configuration.tftpl.json` — state machine wiring (which task runs after which); one per pipeline
- `iac/<pipeline_name>/<task_name>/code/main.py` (or `main.sql`) — task code; Python exposes `def main(job)` returning `{full_table_name: ProcessingResponse}`
- `iac/<pipeline_name>/<task_name>/requirements.txt` — task-specific Python deps
- `iac/<pipeline_name>/<task_name>/code/tables_configuration/<db>.<table>.yaml` *(optional)* — per-output-table metadata; the SDK applies the `description:` to the Glue table and the per-column `schema: <col>: description:` as column comments on every successful ingestion. See `docs/pipelines.md` §"Table metadata".
- `code/<lib_name>/` — Poetry packages shared across tasks. Built and published to the domain's private CodeArtifact repo by `iac/<lib_name>.tf` (the scaffold ships `code/shared_lib/` + `iac/shared_lib.tf` as an example). Tasks consume them via a regular `requirements.txt` pin (`shared-lib>=0.1.0`).

Each pipeline gets its own folder under `iac/` named after the pipeline. The scaffold ships with one pipeline (`{{cookiecutter.pipeline_name}}/`); add more by creating sibling folders and `iac/pipeline_<name>.tf` declarations.

## Tooling
Tool versions (`terraform`, `awscli`, `poetry`) are pinned in `mise.toml` at the repo root. With [mise](https://mise.jdx.dev/) installed, the right versions activate automatically when you cd into the repo. Docker is *not* managed by mise (system daemon) but is required at `terraform apply` time to build task images.

## Framework docs

After `terraform init`, the framework repo is cached locally — that's the canonical reference (matches the deployed `dataplatform_version`). The `domain` segment in the paths below is the Terraform module label (`module "domain" { ... }` in `domain.tf`); if you renamed it, substitute accordingly.

- `iac/.terraform/modules/domain/docs/pipelines.md` — how to author tasks, declare them, wire the state machine
- `iac/.terraform/modules/domain/docs/deploying.md` — provisioning, prerequisites, IAM
- `iac/.terraform/modules/domain/domain_factory/variables.tf` — every domain knob
- `iac/.terraform/modules/domain/pipeline_factory/variables.tf` — every pipeline/task knob
- `iac/.terraform/modules/domain/datalake_sdk/README.md` — SDK runtime API (`job.ingest`, `job.spark_session`, …)

**Claude — if `iac/.terraform/modules/domain/` is missing**, the framework hasn't been pulled locally yet. Run `cd iac && terraform init{% if cookiecutter.terraform_backend_bucket_name %} -backend-config=backend.hcl{% endif %}` (or ask the user to) before relying on the local docs — that command clones the framework repo into `.terraform/modules/` so everything above becomes readable.

Fallback (always latest `prod`): https://github.com/erwan-simon/aws-data-platform-framework

## Conventions
- Tasks' `main.py` exports a top-level `def main(job)` returning a dict; NOT a subclass, no `if __name__ == "__main__"`.
- All managed tables are Iceberg. Ingestion modes: `overwrite`, `append`, `upsert`.
- CSV ingestion requires a header row.
- Resource names follow `{project_name}_{domain_name}_{stage_name}_…`. Stage = active Terraform workspace.
- SQL tasks (`type: "sql"`) require a single `main.sql` and exactly one output table.
- Task-side config goes through `additional_parameters` in `tasks_configuration` (read at runtime via `job.task_additional_parameters`), not new env vars.

## Common operations (high-level — see `docs/pipelines.md` for details)
- **Add a task**: append to `tasks_configuration` in `pipeline.tf`, create `<task_name>/code/main.py` + `<task_name>/requirements.txt`, **add a AWS step function state in `orchestration_configuration.tftpl.json` and wire it into the flow** (this is the easy step to forget).
- **Modify a task's code**: edit `<task_name>/code/main.py`. SDK runtime env vars (`PROJECT_NAME`, `DOMAIN_NAME`, `INPUT_TABLES`, `OUTPUT_TABLES`, …) are injected by Terraform — read them via `job.*`, don't hardcode.
- **Remove a task**: delete its entry in `tasks_configuration`, its state in the orchestration JSON, and its folder.
- **Change the trigger**: edit `trigger` in `pipeline.tf` (schedule cron, EventBridge pattern, or manual invocation).
- **Apply**: `mise run deploy <stage>` (wraps init + workspace select/new + apply with the pinned terraform version).
- **Add a task**: `/new-task [pipeline] [task_name]` — generates the task folder, appends to `tasks_configuration`, and wires the state into the orchestration JSON in one go (the triple that's easy to half-finish manually).
- **Add a pipeline**: `/new-pipeline [name]` — scaffolds `iac/pipeline_<name>.tf` + `iac/<name>/` (orchestration template + optional placeholder task), interactively.
- **Upgrade the framework**: `/update-framework [vX.Y.Z]` (omit the version to take the latest release). The skill diffs the framework between the pinned and target version, surfaces breaking changes and new opt-in features, submits a plan for approval, then patches `iac/` and runs `terraform plan` to verify.

## Starting pipeline
The scaffold ships with a minimal 2-task example: `write_mock_data` (native Python, writes a hardcoded pandas DataFrame coming from the `shared_lib` example library) → `transform` (SQL task that reads `mock_data` and writes `mock_data_transformed`). Replace it with your actual pipeline — it's a placeholder, not a contract.

## Shared Python libraries
The scaffold demonstrates how to share code across tasks via the `code/shared_lib/` Poetry package, built and published to the domain's CodeArtifact repo by `iac/shared_lib.tf`. The `write_mock_data` task imports from it (`from shared_lib.main import build_mock_dataframe`) and pins `shared-lib>=0.1.0` in its `requirements.txt`. When you bump the library's version in `code/shared_lib/pyproject.toml`, the `local.shared_lib_version` in `iac/shared_lib.tf` (read by regex from the pyproject) feeds the task's `additional_rebuild_trigger`, forcing the image to rebuild on the next apply. Delete `code/shared_lib/`, `iac/shared_lib.tf`, the `additional_rebuild_trigger` block, the `depends_on`, and the `shared-lib>=...` line if you don't need a private library.

**Poetry is required on the machine running `terraform apply`** as long as any `code/<lib>/` example is wired in (the external TF module calls `poetry build` to produce the wheel). Removing every shared library wiring drops the Poetry prerequisite.
