# Authoring pipeline tasks

This guide is for **pipeline authors** — the people writing the code that runs inside
the Step Functions state machines provisioned by `pipeline_factory`. For deployment, see
[`deploying.md`](deploying.md); for the SDK surface used inside tasks, see
[`datalake_sdk/README.md`](../datalake_sdk/README.md).

A pipeline is materialized from one Terraform call:

```hcl
module "pipeline" {
  source        = "git::https://github.com/erwan-simon/aws-data-platform-framework.git//pipeline_factory?ref=v1.4.0"
  pipeline_name = "my_pipeline"
  domain_object = module.domain
  orchestration_configuration_template_file_path = "${path.module}/orchestration_configuration.tftpl.json"
  tasks_configuration = { ... }
  trigger             = { ... }
  failure_notification_receivers = ["alerts@example.com"]
}
```

Two artefacts you author yourself: the **task folder(s)** containing the code, and the
**orchestration template** describing how Step Functions chains them.

## Anatomy of a task folder

```
my_task/
├── code/
│   ├── main.py             # OR main.sql for SQL tasks
│   └── tables_configuration/
│       └── my_db.my_table.yaml      # optional metadata
└── requirements.txt        # Python tasks only; pip-installed into the task image. Omit for SQL tasks.
```

The `path` field in `tasks_configuration` points at this folder (the parent of `code/`).
At deploy time, `pipeline_factory`:

1. Detects whether the task is SQL by checking for `code/main.sql` (drives the `IS_SQL_JOB` env var).
2. Builds a Docker image FROM the domain sandbox image, installs `requirements.txt` if present
   (SQL tasks skip this — the SDK is already in the base image), copies `code/` in.
3. Pushes the image to a per-task ECR repository.
4. Wires up an ECS task definition (or EMR Serverless application) referencing that image.

## `tasks_configuration` reference

Each entry is a Terraform object with the following fields:

| Field                          | Required | Description                                                                                                                                                                                                       |
|--------------------------------|----------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `type`                         | yes      | `"python"` or `"sql"`. SQL tasks use `code/main.sql`; Python tasks use `code/main.py`.                                                                                                                            |
| `path`                         | yes      | Relative path to the task folder.                                                                                                                                                                                 |
| `infra_type`                   | yes      | `"ECS"` (Fargate) or `"EMRServerless"`. The latter requires the domain to have `skip_emr_serverless_sandbox_creation = false`.                                                                                    |
| `infra_config`                 | yes      | Map of strings. ECS: `{ cpu = "512", memory = "1024" }`. EMR: leave empty (`{}`); sizing is per-job, set in the orchestration template if needed.                                                                 |
| `input_tables`                 | no       | List of `"db.table"` strings. Lake Formation `SELECT` is granted on each. The database name is stage-prefixed before the LF grant; if a referenced database doesn't exist, `terraform apply` fails with `InvalidInputException: Database not found` — see [troubleshooting](troubleshooting/lakeformation-database-not-found.md).                                                                                                                                                                                                                       |
| `output_tables`                | no       | Map of `"db.table"` → `{ ingestion_mode, upsert_keys, partition_keys }`. Lake Formation `ALL` is granted; `ingestion_mode` is one of `overwrite`, `append`, `upsert`.                                              |
| `additional_parameters`        | no       | Map of strings injected as `TASK_ADDITIONAL_PARAMETERS_*` env vars. Use `key.$ = "$.foo"` to reference values from the trigger payload (Step Functions intrinsic).                                                |
| `additional_rebuild_trigger`   | no       | Arbitrary map. Any change here forces an image rebuild on the next `terraform apply`. Useful when the image depends on something Terraform can't see (e.g., a private library version pulled at build time).     |
| `additional_permissions`       | no       | JSON IAM policy attached to the task role on top of the framework defaults. Pass via `data.aws_iam_policy_document.<x>.json`.                                                                                     |

The full schema lives in [`pipeline_factory/variables.tf`](../pipeline_factory/variables.tf).

## Runtime contract: what your code sees

When a task is invoked by Step Functions, the framework injects this set of environment
variables into the container:

| Env var                            | Set by          | Use                                                                  |
|------------------------------------|-----------------|----------------------------------------------------------------------|
| `PROJECT_NAME` / `DOMAIN_NAME` / `STAGE_NAME` | Terraform | Identify the deployment.                                             |
| `PIPELINE_NAME` / `TASK_NAME`      | Terraform       | Identify the task within its pipeline.                               |
| `INPUT_TABLES`                     | Terraform       | JSON list of `"db.table"` strings, mirrors `tasks_configuration`.    |
| `OUTPUT_TABLES`                    | Terraform       | JSON dict of `"db.table"` → `{ ingestion_mode, upsert_keys, ... }`.  |
| `IS_SQL_JOB`                       | Terraform       | `"true"` if `code/main.sql` exists, else `"false"`.                  |
| `TASK_ADDITIONAL_PARAMETERS_<key>` | Terraform / SFN | One env var per entry of `additional_parameters` (key casing preserved from the Terraform map). |
| `step_function_task_token`         | Step Functions  | Callback token; the SDK uses it to send success / failure to SFN.    |
| `step_function_execution_arn`      | Step Functions  | Identifies the running execution.                                    |
| `step_function_execution_input`    | Step Functions  | JSON-encoded execution input; the SDK parses optional override keys from it (e.g. `logical_date` — see "Overriding the logical date" below). |

You generally don't read these directly — the SDK wrapper does. New per-task config goes
through `additional_parameters`, **not** new env-var plumbing.

## Python tasks

The process entrypoint is **the SDK's wrapper module itself**. At runtime it constructs a
wrapper from the env vars listed above, then does `from main import main` against your task
code and calls `wrapper.execute(main)`. You only write a top-level `main` function that takes
the wrapper instance and returns a dict of `{full_table_name: job.ProcessingResponse(...)}`:

```python
# my_task/code/main.py
from datalake_sdk.base_processing_wrapper import BaseProcessingWrapper

def main(job: BaseProcessingWrapper):
    df = job.read_input_dataset("s3://bucket/raw/file.parquet")
    df = df[df["value"] > 100]
    return {
        "my_db.my_table": job.ProcessingResponse(
            dataframe=df,
            job_end_message="filtered above threshold",
        ),
    }
```

The wrapper class is selected automatically based on `infra_type`: `NativePythonProcessingWrapper`
(Pandas) for ECS, `SparkProcessingWrapper` (PySpark) for EMR Serverless. Both expose the same
surface — the only practical difference inside `main` is the DataFrame type. See
[`datalake_sdk/README.md#library-api`](../datalake_sdk/README.md#library-api) for the public
methods (`read_input_dataset`, `ingest`, `perform_table_maintenance`, …).

For each entry in the returned dict, the SDK ingests the dataframe (applying the
`ingestion_mode` declared in `tasks_configuration`), updates table metadata, and finally sends
a success / failure callback to Step Functions.

## SQL tasks

A SQL task is just `code/main.sql`. Constraints:

- Exactly **one** output table allowed. The SDK runs the query and writes the result with the
  declared `ingestion_mode`.
- The SDK renders `main.sql` through Python `str.format()` before executing it. Three sources of
  placeholders are merged into the context, in this order of precedence:
  1. `{database_prefix}` — stage-aware DB prefix (`{stage_name}_` in non-prod, empty in `prod`).
  2. `{logical_date}` — execution logical date (see "Overriding the logical date" below).
  3. Every key declared in `additional_parameters` (including the dynamic `key.$ = "$.foo"` form
     resolved from the trigger payload, see "Triggers" below) is available as `{key}`.

  Built-in keys (`database_prefix`, `logical_date`) are reserved: declaring an
  `additional_parameters` key with the same name fails the task fast at startup.

```sql
-- my_task/code/main.sql
SELECT id, name, total
FROM {database_prefix}sales.orders
WHERE order_date = DATE '{logical_date}'
  AND tenant = '{tenant_id}';   -- {tenant_id} comes from additional_parameters
```

## ECS vs EMR Serverless

| Choose             | When                                                                                           |
|--------------------|------------------------------------------------------------------------------------------------|
| `ECS` (Fargate)    | Default. Pandas / awswrangler. Up to ~30 GB RAM and 4 vCPU. Faster cold start, simpler cost.   |
| `EMRServerless`    | Datasets that don't fit in Pandas, or jobs that need real distributed shuffles / window functions. |

The SDK contract is identical. Switching is a one-line Terraform change plus a wrapper-class
swap in your code.

## The orchestration template

The Step Functions definition is provided as a `.tftpl.json` template. For each task, drop a
placeholder `${___TASK_NAME_CONFIGURATION___}` (uppercase, surrounded by triple underscores)
where the rendered Step Functions state should land. `pipeline_factory` substitutes each
placeholder with the full task state JSON (resource ARN, parameters, retries, etc.).

```json
{
  "Comment": "Daily refresh",
  "StartAt": "load_orders",
  "States": {
    "load_orders": {
      ${___LOAD_ORDERS_CONFIGURATION___},
      "Next": "aggregate_orders"
    },
    "aggregate_orders": {
      ${___AGGREGATE_ORDERS_CONFIGURATION___},
      "End": true
    }
  }
}
```

You can use any Step Functions feature in the template (Parallel, Map, Choice, …) — see the
multi-branch example shipped in `integration_tests/iac/pipeline_tasks/orchestration_configuration.tftpl.json`.

## Triggers

```hcl
# Cron-based
trigger = {
  type     = "schedule"
  argument = "cron(15 1 * * ? *)"
  parameters = jsonencode({ "hello" = "world!" })   # passed as the SFN execution input
}

# Manual / external trigger only — no scheduler
trigger = {
  type     = "none"
  argument = "none"
}
```

`parameters` becomes the JSON payload of the Step Functions execution. Reference its keys from
`additional_parameters` with the Step Functions intrinsic syntax:

```hcl
additional_parameters = {
  "hello.$"     = "$.hello"   # dynamic, taken from trigger payload at runtime
  "static_key"  = "static_value"
}
```

Inside Python tasks, read these values from `job.task_additional_parameters["hello"]`. Inside
SQL tasks, they are also available as `{hello}` / `{static_key}` placeholders rendered into
`main.sql` at startup — see [SQL tasks](#sql-tasks).

## Overriding the logical date

By default the SDK exposes `job.logical_date` as the Step Functions execution `startDate`
(or today's date when running outside Step Functions). To pin a specific date — typically
for a backfill or replay — pass `{"logical_date": "YYYY-MM-DD"}` in the execution input
when starting the state machine. The framework wires this value through to every task
(ECS native + EMR Spark) automatically; no change to your `main.py` or to the
orchestration template is required.

```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:eu-west-1:...:stateMachine:my_pipeline \
  --input '{"logical_date": "2024-03-15"}'
```

The SDK validates the string against `%Y-%m-%d` and fails the task fast on a malformed
value. Omitting the key keeps the default behaviour — non-breaking for existing schedules
and EventBridge rules.

## Enabling debug logging

By default the SDK configures task loggers at `INFO`. To switch a specific Step Functions
execution to `DEBUG` — useful when investigating a production incident without redeploying
or bumping the SDK — pass `{"debug": true}` in the execution input when starting the state
machine. The framework wires this value through to every task (ECS native + EMR Spark)
automatically; no change to your `main.py` or to the orchestration template is required.

```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:eu-west-1:...:stateMachine:my_pipeline \
  --input '{"debug": true}'
```

The flag raises the level of both the root logger (so boto3, awswrangler and other
underlying libraries also become verbose) and the SDK's own logger. Omitting the key keeps
the default `INFO` behaviour — non-breaking for existing schedules and EventBridge rules.

Accepted values: JSON booleans (`true`/`false`) and their common string equivalents
(`"true"`, `"false"`, `"1"`, `"0"`, case-insensitive). Anything else fails the task fast
at startup — Python's default `bool("false") is True` would silently enable DEBUG, so the
SDK rejects unrecognised values rather than guessing.

## Failure notifications

Set `failure_notification_receivers = ["a@example.com", "b@example.com"]` on the pipeline. The
framework wires a CloudWatch Events rule on Step Functions failures that emails the listed
addresses. The same is wired by the domain factory for failsafe-shutdown events.

## Local Docker execution

Every task can run **locally** in the same Docker image used in production, with a Jupyter
notebook attached for iteration. Useful when developing a new task or debugging an existing one
without redeploying.

Pre-requisites: Docker running, AWS credentials available, and the image either built locally
(`terraform apply` already does that) or pulled from ECR. To pull:

```bash
aws ecr get-login-password --region $ECR_REGION \
  | docker login --username AWS --password-stdin \
      $AWS_ACCOUNT_ID.dkr.ecr.$ECR_REGION.amazonaws.com
```

### ECS task (Pandas, Jupyter)

```bash
docker run \
  -e AWS_PROFILE=$AWS_PROFILE \
  --mount type=bind,source=$HOME/.aws/,target=/root/.aws/ \
  -p 8888:8888 \
  $AWS_ACCOUNT_ID.dkr.ecr.$ECR_REGION.amazonaws.com/$ECR_NAME:$IMAGE_TAG \
  jupyter notebook --ip=0.0.0.0 --no-browser --allow-root
```

The Jupyter URL is printed on stdout — open it in your browser.

### EMR Serverless task (PySpark, Jupyter)

```bash
export CREDENTIALS=$(aws configure export-credentials)
mkdir -p logs

docker run -d \
  -e AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId') \
  -e AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey') \
  -e AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken // ""') \
  -e AWS_REGION=$AWS_REGION -e AWS_DEFAULT_REGION=$AWS_REGION \
  --mount type=bind,source=$(pwd)/logs,target=/var/log/spark/user/ \
  -p 8888:8888 \
  -e PYSPARK_DRIVER_PYTHON=jupyter \
  -e PYSPARK_DRIVER_PYTHON_OPTS='notebook --ip=0.0.0.0 --no-browser' \
  $AWS_ACCOUNT_ID.dkr.ecr.$ECR_REGION.amazonaws.com/$ECR_NAME:$IMAGE_TAG \
  pyspark --master local \
    --conf spark.hadoop.fs.s3a.endpoint=s3.$AWS_REGION.amazonaws.com \
    --conf spark.hadoop.hive.metastore.client.factory.class=com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory

cat logs/stderr   # Jupyter URL is in there
```

To run a single task of an already-deployed pipeline standalone (no Step Functions), prefer
the `datalake_sdk run_task` CLI command — see
[`datalake_sdk/README.md#run_task`](../datalake_sdk/README.md#run_task--execute-one-task-of-a-deployed-pipeline-standalone).

## Table metadata (optional)

Drop a YAML file under `code/tables_configuration/` to document an output table. The SDK
applies it as Glue table description and column comments on every successful ingestion.

```yaml
# my_task/code/tables_configuration/my_db.my_table.yaml
description: "Customer dimension table"
schema:
  customer_id:
    description: "Unique customer identifier"
  customer_name:
    description: "Full name"
```

Independently, the SDK writes a few Glue table properties on every successful write
(`datalake_sdk_upsert_keys`, `datalake_sdk_pipeline_name`, `datalake_sdk_task_name`) — see
[`datalake_sdk/README.md#sdk-managed-glue-table-properties`](../datalake_sdk/README.md#sdk-managed-glue-table-properties).

### Schema validation (optional)

Add a `type:` field to a column to validate its dtype (and optionally its values) before
ingestion. Validation is **opt-in per column** — a column with only a `description:` is left
alone. Columns present in the DataFrame but absent from the YAML are ignored.

```yaml
schema:
  customer_id:
    description: "Unique customer identifier"
    type: bigint
    ge: 1
    unique: true
  customer_name:
    description: "Full name"
    type: string
    nullable: false
  email:
    description: "Primary email"
    type: string
    str_contains: "@"
  status:
    description: "Lifecycle status"
    type: string
    isin: ["new", "validated", "rejected"]
  amount:
    description: "Transaction amount"
    type: decimal(10, 2)
    ge: 0
```

The SDK builds a [Pandera](https://pandera.readthedocs.io/) `DataFrameSchema` from the YAML at
task startup and validates each output DataFrame at the top of `job.ingest(...)`. Spark
DataFrames are validated via `pyspark.pandas` against the **same** schema — no separate
contract to maintain. Failures are collected lazily (every bad column reported in one shot,
not first-fail), the `failure_cases` table is logged, and an `IngestionFailed` is raised —
nothing is written to the table.

**Supported types** (Athena/Iceberg vocabulary):
`string`, `int`, `bigint`, `float`, `double`, `boolean`, `date`, `timestamp`, `decimal(p, s)`.

**Supported checks** (closed list, mapped to Pandera built-ins — keeps the schema
JSON-serializable for versioning):

| YAML keyword     | Effect                                           |
|------------------|--------------------------------------------------|
| `ge`, `gt`, `le`, `lt`, `eq` | Numeric comparison                   |
| `isin`, `notin`              | Value belongs to / outside a list    |
| `str_startswith`, `str_endswith`, `str_contains`, `str_matches` | String patterns |
| `nullable: true\|false`      | Allow nulls (default `true`)         |
| `unique: true\|false`        | Reject duplicates (default `false`)  |

Any other keyword under a column with `type:` makes the task fail at startup (fail-fast,
before the first `ingest()` call).

## Common pitfalls

- **Forgot to bump the SDK version.** If you change `datalake_sdk/`, bump
  `datalake_sdk/pyproject.toml` — otherwise the wheel republished by the domain stays at the
  previous version and your task images pull stale code.
- **EMR task in a domain without the EMR sandbox.** `terraform apply` fails fast. Set
  `skip_emr_serverless_sandbox_creation = false` on the domain, re-apply the domain, then
  deploy the pipeline.
- **SQL task with multiple output tables.** Not supported. Split into separate SQL tasks.
- **CSV input without headers.** The SDK uses schema-on-read; missing headers means missing
  column names.
- **Upsert with non-unique keys in the input dataset.** Detected up front and rejected — the
  SDK refuses to ingest data where a single combination of upsert keys appears twice.
- **`additional_parameters` value is not a string.** Terraform requires every value of the map
  to be a string. JSON-encode if you need to pass a structure, then parse it inside the task.
