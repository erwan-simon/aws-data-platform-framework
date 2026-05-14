# {{cookiecutter.domain_name}}

Data domain built on the [AWS Data Platform Framework](https://github.com/erwan-simon/aws-data-platform-framework).

This repo provisions one domain (`{{cookiecutter.domain_name}}`) under project `{{cookiecutter.project_name}}` in AWS, with one Step Functions pipeline (`{{cookiecutter.pipeline_name}}`). It ships with a placeholder 2-task starter you replace with your real logic.

## What you get out of the box

- An isolated AWS domain: S3 buckets (data + technical), a Glue database, IAM roles, Lake Formation registration, an Athena workgroup, ECR, a private CodeArtifact repo, and (optionally) a Bedrock inference profile.
- A Step Functions pipeline wired to ECS Fargate (and EMR Serverless, if you enable it) with EventBridge scheduling and failure notifications.
- Iceberg-managed tables with ACID transactions, schema evolution, automatic compaction.
- Multi-stage isolation via Terraform workspaces (`dev`, `uat`, `prod`, …).
- All resources tagged for FinOps tracking.

## Prerequisites

Tool versions are pinned in [`mise.toml`](mise.toml). With [mise](https://mise.jdx.dev/) installed (`brew install mise` or `curl https://mise.run | sh`), run `mise install` from the repo root to get the exact `terraform`, `awscli`, and `poetry` versions the scaffold was tested with. Without mise, install the same versions manually.

- Terraform + AWS CLI (versions in `mise.toml`), AWS CLI configured against account `{{cookiecutter.aws_account_id}}` in `{{cookiecutter.aws_region}}`.
- **Docker** running locally — needed at `terraform apply` time to build task images and push them to ECR. Not managed by mise; install Docker Desktop / OrbStack / colima separately.
- A VPC tagged `Name = {{cookiecutter.project_name}}_network_platform_prod` with `Tier`-tagged subnets (Public/Private). The companion [`aws-network-stack`](https://github.com/erwan-simon/aws-network-stack) repo provisions one out of the box.
- The deploying IAM principal must be a Lake Formation admin in the account.
- **[Poetry](https://python-poetry.org/)** on the machine running `terraform apply` — only required because the scaffold ships an example private Python library (`code/shared_lib/`) built and published to CodeArtifact at apply time. Remove the example (see "Shared Python libraries" below) if you don't need a private library and you can drop the Poetry dependency too.
{% if cookiecutter.terraform_backend_bucket_name %}- The S3 bucket `{{cookiecutter.terraform_backend_bucket_name}}` for Terraform state must already exist.
{% else %}- No remote state bucket configured — Terraform state lives locally under `iac/terraform.tfstate.d/`. Move to S3 before going to production.
{% endif %}

## Quickstart

```bash
mise install               # pulls the versions pinned in mise.toml
mise run deploy dev        # init + workspace select/new + apply (replace `dev` with your stage)
```

`mise run deploy` always uses the pinned versions (no need for mise's shell hook to be active). To call terraform directly instead, activate the shell hook (`mise activate zsh|bash|fish` in your shell rc) so the pinned versions take over when you `cd` into the repo, then:

```bash
cd iac
terraform init{% if cookiecutter.terraform_backend_bucket_name %} -backend-config=backend.hcl{% endif %}
terraform workspace new dev    # or: terraform workspace select dev
terraform apply
```

Once the apply succeeds, trigger the pipeline manually from the AWS Step Functions console (state machine name: `{{cookiecutter.project_name}}_{{cookiecutter.domain_name}}_dev_{{cookiecutter.pipeline_name}}`) or wait for the schedule.

## Layout

```
.
├── code/
│   └── shared_lib/                            # example Poetry library shared across tasks
│       ├── pyproject.toml                     # version is read by iac/shared_lib.tf
│       └── shared_lib/                        # Python package; imported by tasks as `shared_lib`
├── iac/
│   ├── domain.tf                              # domain_factory call
│   ├── pipeline.tf                            # pipeline_factory call
│   ├── shared_lib.tf                          # builds + publishes code/shared_lib to CodeArtifact
│   ├── locals.tf, variables.tf, terraform.tf  # supporting TF
│   └── {{cookiecutter.pipeline_name}}/        # one folder per pipeline
│       ├── orchestration_configuration.tftpl.json   # Step Functions state machine
│       └── <task_name>/
│           ├── code/main.py (or main.sql)           # task code
│           ├── code/tables_configuration/*.yaml     # per-output-table descriptions (optional)
│           └── requirements.txt                     # task-specific Python deps
├── CLAUDE.md                                  # Claude Code briefing for this repo
└── .claude/skills/                            # Claude Code skills (see below)
```

Each pipeline lives under `iac/<pipeline_name>/`. Add more by declaring a sibling `iac/pipeline_<name>.tf` and creating the matching folder (the `/new-pipeline` skill does this for you).

## Day-to-day operations

- **Deploy a change**: `mise run plan <stage>` to preview, then `mise run deploy <stage>` to apply (both wrap init + workspace select/new). Or `cd iac && terraform plan && terraform apply` from the right workspace if you prefer to drive terraform yourself.
- **Add a new task**: create `iac/<pipeline>/<task>/code/main.py`, add an entry to `tasks_configuration` in the pipeline's `.tf`, AND add a state in `orchestration_configuration.tftpl.json` (forgetting the third one is the classic mistake). Or use `/new-task` (see below).
- **Add a new pipeline**: declare `iac/pipeline_<name>.tf` and create `iac/<name>/`. Or use `/new-pipeline`.
- **Document a table**: drop a YAML under `iac/<pipeline>/<task>/code/tables_configuration/<db>.<table>.yaml`. The SDK applies it to Glue (table description + column comments) on every successful ingestion.
- **Share code across tasks**: add functions to `code/shared_lib/` (bump the version in its `pyproject.toml`), then `import` from `shared_lib` in any task. The scaffold wires this end-to-end in `write_mock_data`. Add a new library with `code/<lib_name>/` + `iac/<lib_name>.tf` mirroring the `shared_lib` pattern. Requires Poetry on the apply machine — see Prerequisites.

### Shared Python libraries

The scaffold ships `code/shared_lib/` as an example: a tiny Poetry package built and pushed to the domain's CodeArtifact repo by `iac/shared_lib.tf` on every `terraform apply`. Tasks pin it like any other dependency (`shared-lib>=0.1.0` in their `requirements.txt`) and import from `shared_lib`. The library's version (`pyproject.toml`) feeds `local.shared_lib_version` and the task's `additional_rebuild_trigger`, so bumping the version automatically rebuilds the consuming task images on the next apply.

**Removing the example** if you don't need a private library:
- delete `code/shared_lib/` and `iac/shared_lib.tf`
- remove the `shared-lib>=0.1.0` line from `iac/{{cookiecutter.pipeline_name}}/write_mock_data/requirements.txt`
- remove the `additional_rebuild_trigger` block and the `depends_on = [module.shared_lib_deploy]` line from `iac/pipeline.tf`
- revert `iac/{{cookiecutter.pipeline_name}}/write_mock_data/code/main.py` to build the DataFrame inline instead of importing `shared_lib`

Once these are gone, Poetry is no longer needed at apply time.
- **Upgrade the framework**: bump `?ref=` in `iac/domain.tf` + `iac/pipeline.tf` to a new release tag. Or use `/update-framework`.

For the full task-authoring guide, after a first `terraform init`, read `iac/.terraform/modules/domain/docs/pipelines.md` (canonical, pinned to your framework version). Fallback online: [`docs/pipelines.md`](https://github.com/erwan-simon/aws-data-platform-framework/blob/prod/docs/pipelines.md).

## Claude Code integration

This scaffold is **Claude Code aware**. Two things ship out of the box:

### `CLAUDE.md`

A briefing at the repo root that tells Claude:
- where the framework docs live (cached locally after `terraform init`),
- the task contract (`def main(job)` returning a dict, no class subclassing),
- the layout conventions (one folder per pipeline, tables_configuration YAMLs, …),
- and how to avoid the common pitfalls (forgetting the orchestration state when adding a task, hardcoding stage names, etc.).

Open the repo in Claude Code and it picks this up automatically.

### `.claude/skills/`

Three opinionated skills you can trigger as slash-commands:

| Skill | What it does |
|---|---|
| `/new-task [pipeline] [task]` | Scaffolds the task folder (code stub + requirements), appends to `tasks_configuration`, AND wires a state in the orchestration JSON — the triple that's easy to half-finish manually. Asks whether to scaffold a `tables_configuration` YAML per output table. |
| `/new-pipeline [name]` | Creates `iac/pipeline_<name>.tf` (matching the pinned framework version of your existing pipeline) and `iac/<name>/` (orchestration template + optional placeholder task). Interactive: trigger type, starter content, copy from an existing pipeline. |
| `/update-framework [vX.Y.Z]` | Diffs the framework repo between your pinned version and the target (latest by default), surfaces breaking changes *and* new opt-in features, submits a plan for your approval, patches the `?ref=` pins + any required follow-up edits in `iac/` and Python tasks, then runs `terraform plan` to verify. |

All three skills check that your git worktree is clean before editing anything, and submit a plan you approve before any write. They don't commit and don't `terraform apply` — you stay in control.

## Going further

- Framework source: https://github.com/erwan-simon/aws-data-platform-framework
- Deployment guide: [`docs/deploying.md`](https://github.com/erwan-simon/aws-data-platform-framework/blob/prod/docs/deploying.md)
- Pipeline authoring guide: [`docs/pipelines.md`](https://github.com/erwan-simon/aws-data-platform-framework/blob/prod/docs/pipelines.md)
- SDK runtime API: [`datalake_sdk/README.md`](https://github.com/erwan-simon/aws-data-platform-framework/blob/prod/datalake_sdk/README.md)
