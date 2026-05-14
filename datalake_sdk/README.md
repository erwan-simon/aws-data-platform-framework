# datalake_sdk

The runtime SDK and CLI for the [AWS Data Platform Framework](../README.md). Tasks running on
ECS Fargate or EMR Serverless use it to ingest data into Iceberg tables; humans use it to run
ad-hoc operations from a terminal.

It exposes:

- A **CLI** (`datalake_sdk`) with sub-commands for ingestion, table deletion, cross-stage data
  migration, ad-hoc task execution, Lake Formation resource-link sync, and an optional AI agent.
- A **Python library** (`NativePythonProcessingWrapper` / `SparkProcessingWrapper`) used inside
  task code to read input datasets and write Iceberg outputs with retries, partitioning, and
  schema management handled for you.

## Install

### From AWS CodeArtifact (recommended)

The platform's `domain_factory` publishes this package to a private CodeArtifact repository on
every deployment. To consume it, you need an IAM principal with CodeArtifact read access.

```bash
export CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token \
  --domain $CODEARTIFACT_DOMAIN_NAME \
  --domain-owner $AWS_ACCOUNT_ID \
  --query authorizationToken --output text)

pip config set site.index-url \
  https://aws:$CODEARTIFACT_AUTH_TOKEN@$CODEARTIFACT_DOMAIN_NAME-$AWS_ACCOUNT_ID.d.codeartifact.eu-west-1.amazonaws.com/pypi/$CODEARTIFACT_REPOSITORY_NAME/simple/
pip config set site.extra-index-url https://pypi.python.org/simple/

pip install datalake-sdk
datalake_sdk --help
```

### From source

```bash
git clone https://github.com/erwan-simon/aws-data-platform-framework.git
cd aws-data-platform-framework/datalake_sdk
poetry install                  # add `-E agent` for the Datalfred extras
poetry run datalake_sdk --help
```

From the repo root you can also use the wrapped tasks: `mise run sdk-install` (pass `ARGS="-E agent"` for the extra) and `mise run sdk-build`.

For a system-wide install: `poetry build && pip install dist/*.whl`.

### Optional Datalfred agent

The `datalfred` sub-command requires the `[agent]` extra (Bedrock + Strands).

```bash
pip install 'datalake-sdk[agent]'
# or, from source:
poetry install -E agent
```

## CLI

All commands share three required global options that scope every operation to a single
`{project}_{domain}_{stage}` triplet:

```
datalake_sdk -p <project_name> -d <domain_name> -s <stage_name> <command> ...
```

### `ingest` — load a file into an Iceberg table

CSV (must have a header row), Parquet, or JSON Lines. Use `--use-spark` to run the ingestion
through PySpark instead of Pandas (only useful when the file is large enough that Pandas can't
hold it).

```bash
datalake_sdk -p poc -d my_tests -s prd ingest \
  --database-name my_database \
  --table-name my_table \
  --input-file-path ./file.csv \
  --ingestion-mode upsert \
  --upsert-keys "column_1/column_2" \
  --partition-keys "column_3/column_4" \
  --csv-delimiter ";"
```

### `delete_table` — drop a table and its data

Removes the Glue entry **and** the underlying S3 prefix. Asks for interactive confirmation.

```bash
datalake_sdk -p poc -d my_tests -s prd delete_table \
  --database-name my_database --table-name my_table
```

### `migrate_data` — copy a table (or a whole DB) across stages

Reads from `--source-stage-name` via Athena in chunks and re-ingests through the SDK in
`upsert` mode. Useful for refreshing `dev`/`uat` from `prod`.

```bash
datalake_sdk -p poc -d newsroom -s dev migrate_data \
  --source-stage-name prod \
  --database-name newsroom \
  --source-table-name articles \
  --owner-job articles_pipeline/load_articles
```

Highlights:

- Omit `--source-table-name` to replicate every table of the source database.
- `--upsert-keys` falls back to the source table's `datalake_sdk_upsert_keys` Glue property.
- `--owner-job <pipeline>/<task>` grants Lake Formation `ALL` (with grant option) on each target
  table to the corresponding IAM role
  `{project}_{domain}_{target_stage}_{pipeline}_{task}`. Without it, the SDK falls back to the
  `datalake_sdk_pipeline_name` / `datalake_sdk_task_name` properties of the source table; if
  those are missing too, a warning is emitted and the migrating principal becomes the LF owner
  (the original pipeline may then lose access, so the next execution might fail).

### `run_task` — execute one task of a deployed pipeline standalone

Looks up a deployed Step Functions state machine, finds the named task state (ECS or EMR),
and runs it directly — no Step Functions execution, no callback token. Useful for debugging a
single task without re-triggering the whole pipeline.

```bash
datalake_sdk -p poc -d my_tests -s dev run_task \
  --pipeline-name my_pipeline \
  --task-name my_task
```

### `update_foreign_linked_databases` — sync cross-account Glue resource links

When a Glue database from another AWS account is shared with this account via Lake Formation,
it shows up in the local catalog but isn't directly queryable — Athena and most consumers only
see databases that exist as proper local entries. The fix is a Lake Formation
[resource link][lf-resource-link]: a local Glue database whose `TargetDatabase` points at the
foreign catalog ID and database name.

This command reconciles those links: it **creates** a resource link for every shared database
that doesn't have one yet, and **deletes** orphan links whose target has been unshared or
removed. Run it after a new share is granted, after a producer drops a share, or on a
schedule. Operates on databases only — table-level links and column-level grants are not
touched.

```bash
datalake_sdk -p poc -d my_tests -s prd update_foreign_linked_databases
```

[lf-resource-link]: https://docs.aws.amazon.com/lake-formation/latest/dg/resource-links-about.html

### `datalfred` — natural-language agent (optional)

See [Datalfred](#datalfred) below.

## Library API

The library is what task code actually runs against. Two implementations of the same contract:

| Wrapper                          | Backend                | Use when                           |
|----------------------------------|------------------------|------------------------------------|
| `NativePythonProcessingWrapper`  | Pandas + awswrangler   | Small / medium datasets, ECS tasks |
| `SparkProcessingWrapper`         | PySpark                | Large datasets, EMR Serverless     |

Both expose the same surface: `read_input_dataset(path, ...)`, `ingest(table, df)`,
`perform_table_maintenance(table)`, plus an `execute()` lifecycle for full task runs.

### Ad-hoc ingestion

```python
from datalake_sdk.native_python_processing_wrapper import NativePythonProcessingWrapper

wrapper = NativePythonProcessingWrapper(
    project_name="poc",
    domain_name="my_tests",
    stage_name="prd",
    output_tables={
        "my_database.my_table": {
            "ingestion_mode": "upsert",
            "upsert_keys": ["id"],
            "partition_keys": ["d_date"],
        },
    },
)

df = wrapper.read_input_dataset("./file.csv", csv_delimiter=";")
wrapper.ingest("my_database.my_table", df)
```

For PySpark, swap the import: `from datalake_sdk.spark_processing_wrapper import SparkProcessingWrapper`.

### Pipeline task: define a top-level `main` function

For tasks deployed by `pipeline_factory`, the process entrypoint is **the SDK's wrapper
module itself**. At runtime it constructs a wrapper from env vars set by Terraform / Step
Functions, then does `from main import main` against your task code and calls
`wrapper.execute(main)`.

What you write is one top-level function that takes the wrapper instance and returns a dict
of `{full_table_name: job.ProcessingResponse(...)}`:

```python
# code/main.py
from datalake_sdk.base_processing_wrapper import BaseProcessingWrapper

def main(job: BaseProcessingWrapper):
    df = job.read_input_dataset("s3://bucket/input.csv")
    df = df[df["value"] > 100]
    return {
        "output_db.output_table": job.ProcessingResponse(
            dataframe=df,
            job_end_message="filtered rows above threshold",
        ),
    }
```

The SDK then ingests every dataframe in the returned dict, applies any table metadata, and
sends the success/failure callback to Step Functions. SQL tasks need no Python code at all —
see [`docs/pipelines.md`](../docs/pipelines.md) for the SQL contract and the rest of the
task-authoring picture.

## Ingestion modes

### overwrite

Replace all existing data with the ingested dataset.

| Before          | Ingested        | After           |
|-----------------|-----------------|-----------------|
| toto / 1 / 123  | toto / 3 / 28932 | toto / 3 / 28932 |
| tata / 2 / 9823 |                 |                  |

### append

Add the ingested rows; existing rows are untouched. Can produce duplicates.

| Before          | Ingested         | After            |
|-----------------|------------------|------------------|
| toto / 1 / 123  | toto / 3 / 28932 | toto / 1 / 123   |
| tata / 2 / 9823 |                  | tata / 2 / 9823  |
|                 |                  | toto / 3 / 28932 |

### upsert

Update rows matching `upsert_keys`, insert the others. Requires `upsert_keys` to be unique
within the ingested dataset — duplicates are detected up front and abort the ingestion.

| Before (keys: col_1, col_2) | Ingested        | After            |
|-----------------------------|-----------------|------------------|
| toto / 1 / 123              | toto / 3 / 28932 | toto / 1 / 123  |
| tata / 2 / 9823             | tata / 2 / 1034  | toto / 3 / 28932 |
|                             |                  | tata / 2 / 1034  |

## Iceberg & automatic maintenance

All managed tables are Apache Iceberg, format version 2 (Athena-compatible), with extended
commit-retry properties (`commit.retry.num-retries=30`, `min-wait-ms=120s`, `max-wait-ms=600s`)
to absorb concurrent writes.

The SDK runs maintenance on a table every 10 versions, or on demand:

```python
wrapper.perform_table_maintenance("my_database.my_table", force_maintenance=True)
```

Under the hood:

```sql
VACUUM   my_database.my_table;
OPTIMIZE my_database.my_table REWRITE DATA USING BIN_PACK;
```

### SDK-managed Glue table properties

On every successful `ingest()`, the SDK records on the Glue table:

- `datalake_sdk_upsert_keys` — comma-separated upsert keys (only for `upsert` mode). A warning
  is emitted if the new value differs from a previously stored one.
- `datalake_sdk_pipeline_name` / `datalake_sdk_task_name` — taken from `PIPELINE_NAME` /
  `TASK_NAME` env vars (skipped for ad-hoc CLI ingestions).

These are read back by `migrate_data` to default `--upsert-keys` and `--owner-job`.

## Datalfred

Bedrock-backed conversational agent for the lake. Routes questions to three sub-agents:

- **Data Analyst** — lists databases/tables, runs Athena queries.
- **Code Debugger** — analyses pipeline code and configuration.
- **Run Guy** — executes ingestions and SDK commands on your behalf.

```bash
# Interactive
datalake_sdk -p poc -d my_tests -s prd datalfred --model-size large

# One-shot
datalake_sdk -p poc -d my_tests -s prd datalfred \
  --model-size small \
  --user-prompt "List all tables in the analytics database"

# Resume a session (S3-backed when --session-id is given)
datalake_sdk -p poc -d my_tests -s prd datalfred \
  --session-id my-session-123 --model-size medium
```

`--model-size` is `small`, `medium`, or `large`; each maps to a Bedrock inference profile
provisioned by `domain_factory` (`{project}_{domain}_{stage}_{model_size}`). Token usage and
estimated cost are printed at the end of each run.

If the domain was deployed with `enable_llm = false`, no inference profiles exist for it and
`datalfred` raises a clear error pointing back at the `domain_factory` flag.

## Reference pointers

- CLI options for each command: see the `@click.option` definitions in
  [`datalake_sdk/`](datalake_sdk/). `datalake_sdk <command> --help` works too.
- Runtime contract (env vars set for tasks, Step Functions integration, SQL job mode): see
  [`docs/pipelines.md`](../docs/pipelines.md).
- Naming conventions, stage prefixes, deployment specifics: see the [root README](../README.md)
  and [`docs/deploying.md`](../docs/deploying.md).
