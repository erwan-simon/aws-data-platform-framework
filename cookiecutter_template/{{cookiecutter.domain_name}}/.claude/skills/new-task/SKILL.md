---
name: new-task
description: Add a task to an existing pipeline. Generates the task folder (code stub + requirements), appends an entry to `tasks_configuration` in the pipeline's `.tf`, AND wires a state into the orchestration JSON — the easy-to-forget triple that breaks every manual edit.
---

# new-task

Add a task to an existing pipeline.

Invocation: `/new-task [pipeline] [task_name]`. Either arg may be omitted; ask if missing.

## Why a skill

Adding a task touches three places that must agree:

1. `iac/<pipeline>/<task>/` — code + requirements.
2. `tasks_configuration` map in the pipeline's `.tf` — declares the task to `pipeline_factory`.
3. `iac/<pipeline>/orchestration_configuration.tftpl.json` — adds a state and wires it into the flow.

Forgetting (3) is the classic mistake: `terraform apply` succeeds, but Step Functions never invokes the task.

## Procedure

0. **Working tree must be clean.** `git status --porcelain` empty, else stop and ask the user to commit/stash. Do not stash on their behalf.

1. **Resolve target pipeline.** List sibling folders under `iac/` that are pipelines (contain an `orchestration_configuration.tftpl.json`). If only one exists, use it; otherwise ask. Save as `PIPELINE`. Locate its `.tf` file by grepping `module "pipeline*"` blocks in `iac/*.tf` whose `pipeline_name = "<PIPELINE>"` — save as `PIPELINE_TF`.

2. **Collect inputs.** Ask one batch:
   - **Task name** (snake_case, `^[a-z][a-z0-9_]*$`). Reject if `iac/<PIPELINE>/<name>/` already exists or if the name is already a key in `tasks_configuration`.
   - **Type**: `python` (native Pandas, runs on ECS), `sql` (single `main.sql`, exactly one output table), `pyspark` (runs on EMR Serverless).
   - **Infra**: `ECS` (default for python/sql) or `EMR` (default for pyspark). Warn loudly if the user pairs `python`+`EMR` or `pyspark`+`ECS` — possible but usually wrong.
   - **Input tables**: comma-separated `<domain>.<table>` names (may be empty).
   - **Output tables**: list of `<domain>.<table>` + ingestion mode (`overwrite`, `append`, `upsert`). SQL tasks accept exactly one.
   - **Upsert keys** (if any output uses `upsert`): list of column names per output.
   - **Position in the flow**: after which existing state (the new state becomes its `Next`); or as a parallel branch from an existing state. Default: linearly append after the current terminal state.
   - **Additional parameters** (optional, free-form key/value passed via `additional_parameters`).

3. **Read the framework task contract** to make sure the generated stub matches the current SDK API: open `iac/.terraform/modules/domain/datalake_sdk/datalake_sdk/base_processing_wrapper.py` for the `ProcessingResponse` shape and `iac/.terraform/modules/domain/docs/pipelines.md` for the authoring rules. If `.terraform/modules/domain/` is missing, ask the user to run `cd iac && terraform init` first.

4. **Submit a plan.** Before any edit, present:
   ```
   New task: <name>  (type=<type>, infra=<infra>) in pipeline <PIPELINE>

   Files to create:
     - iac/<PIPELINE>/<name>/code/main.py  (or main.sql)
     - iac/<PIPELINE>/<name>/requirements.txt

   Files to edit:
     - <PIPELINE_TF>:
         + tasks_configuration["<name>"] = { type, path, infra_type, input_tables, output_tables, ... }
     - iac/<PIPELINE>/orchestration_configuration.tftpl.json:
         + new state "<name>" with ${___<NAME_UPPER>___CONFIGURATION___} placeholder
         + rewires <predecessor>.Next → "<name>", and "<name>".Next → <successor> (or End: true)
   ```
   Wait for explicit approval.

5. **Generate files.**

   - **`iac/<PIPELINE>/<name>/code/main.py`** (python/pyspark) — minimal stub: `import` from `datalake_sdk.base_processing_wrapper`, `def main(job):` building a trivial DataFrame, returning `{ "<domain>.<output_table>": job.ProcessingResponse(dataframe=...) }`. For pyspark, use `job.spark_session`. For each input table declared, add a TODO showing `job.input_tables` usage.
   - **`iac/<PIPELINE>/<name>/code/main.sql`** (sql) — minimal `SELECT * FROM <domain>.<first_input_table>` with a comment showing the output table will receive whatever this query returns. Reject if no input tables provided (SQL tasks always need at least one).
   - **`iac/<PIPELINE>/<name>/requirements.txt`** — empty for SQL tasks; `pandas` (or `pyspark` lib pins) for python/pyspark. Don't include `datalake_sdk` — it's pre-installed in the runtime image.
   - **Optional — table metadata YAML.** For each output table declared, ask the user whether to generate `iac/<PIPELINE>/<name>/code/tables_configuration/<db>.<table>.yaml`. If yes, scaffold a minimal file with an empty `description:` and a `schema:` block listing the columns the user expects (each with an empty `description:`) — the user fills the descriptions later. The SDK reads these YAMLs on every successful ingestion and applies them as Glue table description + column comments. See `iac/.terraform/modules/domain/docs/pipelines.md` §"Table metadata" for the exact format. Skip this step if the user declines.

6. **Edit `tasks_configuration`** in `PIPELINE_TF`. Append the new entry preserving the surrounding formatting. Set `path = "<PIPELINE>/<name>"`. Include `additional_parameters` only if the user provided any.

7. **Edit the orchestration JSON.** Insert a new state with the `${___<NAME_UPPER>___CONFIGURATION___}` placeholder (pipeline_factory expands it at apply time). Rewire `Next`/`End` according to the chosen position. Validate the JSON is parseable before saving.

8. **Report next steps.** Tell the user:
   - Replace the stub `main.py`/`main.sql` with the real logic.
   - `cd iac && terraform plan` to validate the wiring. Don't `apply` automatically.
   - Don't commit — let the user review the multi-file diff first.

## Guardrails

- Never silently overwrite an existing task folder or `tasks_configuration` entry — abort with a clear message.
- SQL tasks: exactly one output table, at least one input table — enforce before generating.
- Validate the orchestration JSON parses after the edit. If it doesn't, revert the file and stop.
- Don't run `terraform apply`. Don't commit.
