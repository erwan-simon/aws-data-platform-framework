# CLAUDE.md — {{cookiecutter.domain_name}}

Domain on the [AWS Data Platform Framework](https://github.com/erwan-simon/aws-data-platform-framework).

## Layout
- `iac/domain.tf` — provisions the domain (S3, Glue DB, IAM, Lake Formation, …)
- `iac/pipeline.tf` — declares the Step Functions pipeline; `tasks_configuration` is the canonical list of tasks
- `iac/integration_tests_pipeline/orchestration_configuration.tftpl.json` — state machine wiring (which task runs after which)
- `iac/integration_tests_pipeline/<task_name>/code/main.py` (or `main.sql`) — task code; Python exposes `def main(job)` returning `{full_table_name: ProcessingResponse}`
- `iac/integration_tests_pipeline/<task_name>/requirements.txt` — task-specific Python deps
- `iac/utils/` — optional shared Python lib published to CodeArtifact and importable from tasks

## Framework docs

After `terraform init`, the framework repo is cached locally — that's the canonical reference (matches the deployed `dataplatform_version`). The `domain` segment in the paths below is the Terraform module label (`module "domain" { ... }` in `domain.tf`); if you renamed it, substitute accordingly.

- `iac/.terraform/modules/domain/docs/pipelines.md` — how to author tasks, declare them, wire the state machine
- `iac/.terraform/modules/domain/docs/deploying.md` — provisioning, prerequisites, IAM
- `iac/.terraform/modules/domain/domain_factory/variables.tf` — every domain knob
- `iac/.terraform/modules/domain/pipeline_factory/variables.tf` — every pipeline/task knob
- `iac/.terraform/modules/domain/datalake_sdk/README.md` — SDK runtime API (`job.ingest`, `job.spark_session`, …)

**Claude — if `iac/.terraform/modules/domain/` is missing**, the framework hasn't been pulled locally yet. Run `cd iac && terraform init -backend-config=backend.hcl` (or ask the user to) before relying on the local docs — that command clones the framework repo into `.terraform/modules/` so everything above becomes readable.

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
- **Apply**: `cd iac && terraform init -backend-config=backend.hcl && terraform workspace select <stage> && terraform apply`.

## Why the initial pipeline looks like this
The pipeline you find here at scaffold time (5 tasks: `test_native_write`, `test_native_sql_entrypoint`, `test_spark_write`, `test_spark_sql_entrypoint`, `check_and_clean`) is the **framework's own integration test fixture** — it exists to exercise every feature end-to-end (native + Spark, SQL transforms, upsert, empty-DF, table maintenance, validation, cleanup) so the framework can be deployed and asserted on by CI.

Treat it as a working **reference model**, not as something to preserve: read it when in doubt about a real-world task shape, then **gut, rename, or rewrite** it freely to match the actual pipeline this domain needs. The associated `lakeformation.tf`, `additional_permissions_policy.tf`, `code_pipeline_utils.tf` and `utils/` are documented inline as test-only — drop them once they're not relevant.
