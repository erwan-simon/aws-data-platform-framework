# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo overview

AWS-based data lake platform with three top-level pieces:

- `datalake_sdk/` — Python package + CLI (`datalake_sdk`) used both by humans and by tasks at runtime to ingest data into Iceberg tables. Two processing wrappers (`native_python_processing_wrapper.py` for Pandas/ECS, `spark_processing_wrapper.py` for EMR Serverless) share `base_processing_wrapper.py`. `datalfred_agent/` is the Bedrock-backed agent (optional `[agent]` extra).
- `domain_factory/` — Terraform module that provisions per-domain foundation: S3 (data + technical), Glue DB, Lake Formation registration, Athena workgroup, IAM, ECS/EMR sandbox base images, CodeArtifact repo (which it also uses to publish the SDK), failsafe-shutdown Lambda, Bedrock inference profile. Its `outputs.tf` exports a `domain_object` consumed by `pipeline_factory`.
- `pipeline_factory/` — Terraform module that builds a Step Functions pipeline from a `tasks_configuration` map. Tasks are either ECS Fargate (`modules/ecs_factory/`) or EMR Serverless (`modules/emr_factory/`). Each task's image is built/pushed via `modules/build_and_upload_image_to_ecr/` on top of the domain sandbox image. Step Functions state machine is rendered from a `.tftpl.json` template provided by the caller.
- `cookiecutter_template/` — Scaffold for new domains. Emits a minimal 2-task pipeline (`write_mock_data` → `transform`, no Spark, EMR sandbox off by default) — meant to be gutted/rewritten by the user. This template is itself one of the two integration-test targets (see `integration_tests/`).
- `integration_tests/` — In-tree, framework-owned domain that exercises every platform feature end-to-end (5 tasks: native + Spark, SQL entrypoints, upsert, table maintenance, validation, cleanup). Deployed and run by CI like a real domain. Not a cookiecutter target — values are baked in (project=poc, domain=datalake_test, pipeline=tests).

The SDK version in `datalake_sdk/pyproject.toml` is parsed by `domain_factory/locals.tf` and is what gets published to CodeArtifact — bump it when SDK changes need to land in deployed tasks.

## Common commands

Tool versions (terraform, python, poetry, awscli) are pinned in `mise.toml` at the repo root. If [mise](https://mise.jdx.dev/) is installed, the right versions activate automatically when you cd into the repo; otherwise install the versions listed in `mise.toml` manually. The scaffold has its own `mise.toml` with a slightly different toolset.

SDK (run from `datalake_sdk/`):
```bash
poetry install                  # with [agent] extra: poetry install -E agent
poetry run datalake_sdk --help
poetry build                    # produces dist/*.whl
```

Integration tests (run against the live AWS account — `scripts/run_integration_tests.sh` does `terraform init/apply` then polls the state machine):
```bash
# Required env: ACCOUNT_ID, AWS_DEFAULT_REGION, PROJECT_NAME=poc, STAGE_NAME=<workspace>,
#               TERRAFORM_BACKEND_BUCKET, TERRAFORM_BACKEND_DYNAMODB

# Full fixture (in-tree, 5 tasks):
bash scripts/run_integration_tests.sh integration_tests/iac datalake_test tests

# Minimal cookiecutter scaffold (generated into _integration_test/datalake_scaffold/):
bash scripts/generate_scaffold.sh
bash scripts/run_integration_tests.sh _integration_test/datalake_scaffold/iac datalake_scaffold main
```

There is no repo-wide lint/test runner; CI stages are `init`, `format`, `security`, `unit_tests`, `integration_tests` (two parallel jobs: `integration_tests_full_fixture`, `integration_tests_scaffold`).

## Conventions that affect code changes

- **Stage-derived naming.** Every AWS resource is `{project_name}_{domain_name}_{stage_name}_...`. Glue DB names are prefixed with `{stage_name}_` for non-prod and unprefixed when `stage_name == "prod"` (see "Naming Conventions" in README §IX). Don't hardcode names — read from the domain object.
- **Stage source.** In CI: `$CI_COMMIT_REF_SLUG`. Locally: the active Terraform workspace. Never assume a stage value.
- **Task runtime contract.** Tasks read everything from env vars set by Terraform: `PROJECT_NAME`, `DOMAIN_NAME`, `STAGE_NAME`, `PIPELINE_NAME`, `TASK_NAME`, `INPUT_TABLES` (JSON list), `OUTPUT_TABLES` (JSON dict), `IS_SQL_JOB`, `TASK_ADDITIONAL_PARAMETERS_*`, plus `step_function_task_token` / `step_function_execution_arn` injected by Step Functions. New per-task config goes through `additional_parameters` in `tasks_configuration`, not new env-var plumbing.
- **SQL tasks** (`type: "sql"`) require a `main.sql` file and support exactly one output table.
- **Iceberg-only.** All managed tables are Iceberg; ingestion modes are `overwrite`, `append`, `upsert` (the SDK retries Iceberg commit conflicts up to 30× with 2–10 min waits).
- **CSV ingestion** requires a header row.

## Commit / release

Conventional Commits are required — `semantic-release` on the `prod` branch derives the next version from them, and `domain_factory` then republishes the SDK from `datalake_sdk/pyproject.toml`.
