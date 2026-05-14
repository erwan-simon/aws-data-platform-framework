# Deploying the platform

This guide is for platform / DevOps engineers standing the framework up in a real AWS account.
For the SDK or pipeline-authoring perspective, see [`datalake_sdk/README.md`](../datalake_sdk/README.md)
and [`pipelines.md`](pipelines.md).

The framework consists of two Terraform modules that you compose:

- [`domain_factory/`](../domain_factory) — provisioned **once per business domain**. Stands up
  the foundation: storage, catalog, governance, IAM, sandbox images.
- [`pipeline_factory/`](../pipeline_factory) — provisioned **as many times as needed inside a
  domain**. Each invocation creates a Step Functions state machine and the tasks that go with it.

You consume them either by scaffolding a new project from
[`cookiecutter_template/`](../cookiecutter_template) (a minimal 2-task starter; one of the two
domains CI deploys for integration tests, the other being the feature-exhaustive
[`integration_tests/`](../integration_tests)) or by referencing them from a remote `git::`
source pinned to a release tag — the latter is the production pattern described below.

## Prerequisites

### Accounts and tooling

Tool versions for working on this repo are pinned in [`mise.toml`](../mise.toml). With
[mise](https://mise.jdx.dev/) installed (`brew install mise` or `curl https://mise.run | sh`),
`mise install` gives you the exact `terraform`, `python`, `poetry`, and `awscli` versions.
Scaffolded domains have their own [`mise.toml`](../cookiecutter_template/{{cookiecutter.domain_name}}/mise.toml)
with a smaller toolset (no Python; Poetry only if the `shared_lib` example is kept). Without
mise, install the same versions manually.

- AWS account with rights to create S3, Glue, Lake Formation, IAM, ECS, EMR Serverless, Step
  Functions, Lambda, EventBridge, CloudWatch, ECR, CodeArtifact, Bedrock resources.
- AWS CLI configured (version pinned in `mise.toml`).
- Terraform (version pinned in `mise.toml`); AWS provider `>= 5.60.0, < 6.14.0`.
- **Docker** running locally — Terraform invokes it to build task and sandbox images. Not
  managed by mise; install Docker Desktop / OrbStack / colima separately.
- Python and Poetry (versions pinned in `mise.toml`) — needed to build/publish the SDK
  manually and for any domain that ships a private Python library (`code/<lib>/` pattern).

### Pre-existing infrastructure

The framework expects these resources to already exist in the target account:

- **Terraform state backend.** An S3 bucket and a DynamoDB table for state and locking.
- **VPC.** A VPC tagged `Name = {project_name}_network_platform_prod`, containing subnets
  tagged `Tier = Public` and/or `Tier = Private`. The factories pick subnets by tag, not by ID.
  The companion [`aws-network-stack`](https://github.com/erwan-simon/aws-network-stack) repo
  provisions a VPC with the right `Name`/`Tier` tags out of the box.
- **NAT gateway**, if you set `use_public_subnets = false` — tasks need outbound internet access
  to reach AWS APIs and ECR. [`aws-network-stack`](https://github.com/erwan-simon/aws-network-stack)
  can provision one via its `nat_gateways_count` variable.
- **Lake Formation** must be enabled in the region (default settings are fine; the framework
  registers locations as it deploys). Whoever runs `terraform apply` must already be a Lake
  Formation admin in the account, or the data-location registration step fails.
- **Bedrock**, if you want the Datalfred agent. Model access must be granted in the region.
  Set `enable_llm = false` on the `domain_factory` module to opt out: no inference profiles are
  created and pipeline failures skip the Datalfred investigation in the failsafe-shutdown Lambda.

## Building your deployment

The repo's [`cookiecutter_template/`](../cookiecutter_template) is a minimal starter
(2-task pipeline you'll replace) wired to the right module sources. The easiest way to use it is
to invoke cookiecutter directly against the remote repo (no clone needed):

```bash
pip install cookiecutter
cookiecutter https://github.com/erwan-simon/aws-data-platform-framework --directory cookiecutter_template
```

Any cookiecutter variable can be pre-filled with a positional `key=value` argument — handy for
values you'd otherwise paste from the shell:

```bash
cookiecutter https://github.com/erwan-simon/aws-data-platform-framework \
  --directory cookiecutter_template \
  aws_account_id=$(aws sts get-caller-identity --query Account --output text) \
  aws_region=$(aws configure get region) \
  dataplatform_version=$(git ls-remote --tags https://github.com/erwan-simon/aws-data-platform-framework | awk -F'/' '{print $NF}' | grep -v '\^{}$' | sort -V | tail -1)
```

Then `cd <your_domain_name>/iac`, `terraform init -backend-config=backend.hcl`, and
`terraform apply` (see the [root README quickstart](../README.md#quickstart) for the full flow).
Cookiecutter generates `backend.hcl` from the `terraform_backend_bucket_name` prompt; if you
leave that prompt empty, the scaffold uses a local Terraform backend (state stored under
`iac/terraform.tfstate.d/`), `backend.hcl` is not generated, and you just run `terraform init`
without `-backend-config`.
For your own deployment, the recommended pattern is to consume the modules as remote git
sources, pinned to a release tag.

A minimal `main.tf`:

```hcl
terraform {
  backend "s3" {
    key            = "my_domain.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    bucket         = "your-tf-backend-bucket"
    dynamodb_table = "your-tf-backend-table"
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.60.0, < 6.14.0" }
  }
}

provider "aws" {
  region = "eu-west-1"
  default_tags {
    tags = {
      Appli     = "my_project"
      Component = "my_domain"
      Env       = terraform.workspace
    }
  }
}

module "domain" {
  source       = "git::https://github.com/erwan-simon/aws-data-platform-framework.git//domain_factory?ref=v1.4.0"
  project_name = "my_project"
  domain_name  = "my_domain"
  stage_name   = terraform.workspace
  git_repository                 = "https://github.com/your-org/your-repo"
  failure_notification_receivers = ["alerts@example.com"]
  datalake_admin_principal_arns  = [data.aws_iam_role.admin.arn]
}

module "pipeline" {
  source        = "git::https://github.com/erwan-simon/aws-data-platform-framework.git//pipeline_factory?ref=v1.4.0"
  pipeline_name = "my_pipeline"
  domain_object = module.domain
  orchestration_configuration_template_file_path = "${path.module}/orchestration_configuration.tftpl.json"

  tasks_configuration = {
    "my_task" = {
      type       = "python"
      path       = "./my_task/"
      infra_type = "ECS"
      infra_config  = { cpu = "512", memory = "1024" }
      output_tables = {
        "my_domain.my_table" = {
          ingestion_mode = "upsert"
          upsert_keys    = ["id"]
          partition_keys = ["d_date"]
        }
      }
    }
  }

  trigger = {
    type     = "schedule"
    argument = "cron(15 1 * * ? *)"
  }
  failure_notification_receivers = ["alerts@example.com"]
}
```

Then:

```bash
terraform init -backend-config="bucket=$BUCKET" -backend-config="dynamodb_table=$TABLE"
terraform workspace new dev
terraform apply
```

Pin to a specific framework release (`?ref=v1.4.0`); upgrades are deliberate. The scaffold ships
a Claude Code skill — `/update-framework [vX.Y.Z]` — that diffs the framework between the pinned
and target version, surfaces breaking changes and new opt-in features, submits a plan for
approval, then patches `iac/` and runs `terraform plan` to verify.

For the full task-authoring picture (the structure of `my_task/`, the orchestration template,
how runtime env vars are wired), see [`pipelines.md`](pipelines.md).

## What `domain_factory` provisions

Per call, in your target AWS account:

| Category        | Resources                                                                                                                                              |
|-----------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Storage**     | `{project}-{domain}-{stage}-data` (Iceberg data, intelligent tiering) and `{project}-{domain}-{stage}-technical` (Athena query results, logs) S3 buckets |
| **Catalog**     | A Glue database (`{stage_prefix}{domain_name}`) registered in Lake Formation                                                                           |
| **Governance**  | Lake Formation data-location registration; admin principals from `datalake_admin_principal_arns`                                                       |
| **Querying**    | An Athena workgroup `{project}_{domain}_{stage}` writing results to the technical bucket                                                               |
| **Networking**  | A security group for tasks; subnets are picked from the VPC by `Tier` tag                                                                              |
| **Compute**     | An ECS cluster with a sandbox image; optionally an EMR Serverless application + sandbox image (see [EMR sandbox](#emr-sandbox-creation))               |
| **AI**          | A Bedrock inference profile per model size (`small`, `medium`, `large`) for Datalfred (skipped when `enable_llm = false`)                              |
| **Packaging**   | A private CodeArtifact repository, into which `datalake_sdk` is built and published                                                                    |
| **Operations**  | A failsafe-shutdown Lambda that kills tasks running past a configured duration; an EMR Studio for interactive Spark dev                                |

Configurable knobs are documented in [`domain_factory/variables.tf`](../domain_factory/variables.tf)
— the source is the canonical reference, keep it open while you compose your call. The ones
you'll actually touch:

- `datalake_admin_principal_arns` — IAM ARNs that get full Lake Formation rights on every DB
  and table created by this domain. Usually your CI role plus an administrator role.
- `use_public_subnets` (default `true`) — set to `false` if you want tasks in private subnets
  (requires a NAT Gateway in the VPC).
- `skip_emr_serverless_sandbox_creation` (default `true`) — see below.
- `failure_notification_receivers` — emails wired to CloudWatch Events for task failures.

### EMR sandbox creation

The EMR Serverless sandbox image is **expensive to build** (roughly 30 min) and useless if you
don't plan to run Spark tasks, so it's skipped by default. If any pipeline in this domain has
a task with `infra_type = "EMRServerless"`, you **must** set
`skip_emr_serverless_sandbox_creation = false` on the domain *before* deploying that pipeline —
pipeline EMR images are built on top of the domain's EMR sandbox, so without it the pipeline
`terraform apply` fails fast with a clear error.

## What `pipeline_factory` provisions

Each call (one per pipeline) creates:

- An AWS Step Functions state machine, rendered from the
  `orchestration_configuration_template_file_path` you provide (a `.tftpl.json` template that
  references your tasks).
- One ECS task definition or EMR Serverless application per entry in `tasks_configuration`.
- An ECR repository per task, with the task's Docker image built (on top of the domain
  sandbox image) and pushed during `terraform apply`.
- An EventBridge schedule (if `trigger.type = "schedule"`) that calls `StartExecution` with the
  trigger parameters.
- IAM roles per task (`{project}_{domain}_{stage}_{pipeline}_{task}`), with Lake Formation
  grants on the declared `input_tables` and `output_tables`.
- CloudWatch log groups (30-day retention).
- A failure CloudWatch Events rule that emails the `failure_notification_receivers`.
- An optional pipeline-scoped Glue database (`{stage_prefix}{pipeline_name}`), unless
  `skip_pipeline_database_creation = true`.

Variables: [`pipeline_factory/variables.tf`](../pipeline_factory/variables.tf). The structure of
`tasks_configuration` is detailed in [`pipelines.md`](pipelines.md).

## Stages, workspaces, and naming

Stages (`dev`, `uat`, `prod`, …) are derived **at deployment time**, never hardcoded:

- In **GitLab CI**: from the branch slug (`$CI_COMMIT_REF_SLUG`).
- **Locally**: from the active Terraform workspace (`terraform.workspace`).

Resource names follow `{project_name}_{domain_name}_{stage_name}_…`. Glue databases get a
`{stage_name}_` prefix for non-prod stages; `prod` databases are unprefixed (so `prod` is
queryable at its short name and `dev_*` lives next to it without collision).

Switching environments locally:

```bash
terraform workspace select dev      # or `terraform workspace new dev` the first time
terraform apply
```

If you skip the workspace selection and apply against `default`, you'll deploy a
`default`-prefixed environment — annoying to clean up. Always select first.

## CodeArtifact and the SDK publishing flow

`domain_factory` provisions a private CodeArtifact repository **and** publishes the
`datalake_sdk` wheel into it on every `terraform apply`. The version is read from
[`datalake_sdk/pyproject.toml`](../datalake_sdk/pyproject.toml) by `domain_factory/locals.tf`.

This means: if your task code depends on a new SDK feature, **bump
`datalake_sdk/pyproject.toml` before deploying** — otherwise the wheel republished by the
domain stays at the previous version, and your task images will pull stale code.

Pipeline task images are built FROM the domain sandbox image (which itself bakes in the SDK
from CodeArtifact) and add the task's own dependencies and code on top.

## CI/CD: GitLab is the source of truth

All CI runs in [`.gitlab-ci.yml`](../.gitlab-ci.yml). The stages are: `init`, `format`,
`security`, `unit_tests`, `integration_tests` (two parallel jobs — one deploys+runs the in-tree
[`integration_tests/`](../integration_tests) full fixture, the other generates the cookiecutter
scaffold and deploys+runs that), `mirror_to_github`.

GitHub is a **read-only mirror**. The only thing that runs there is
[`.github/workflows/`](../.github/workflows/) `semantic-release`, which on every push to `prod`
reads the Conventional Commits since the last release and creates a new tag. That tag is what
you reference from `?ref=` in your `git::` Terraform sources.

Conventional Commits are therefore mandatory — `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`,
etc. The version bump (major/minor/patch) is derived from the prefixes.

## Operational notes

- **Failsafe shutdown.** The domain Lambda monitors task run-time and kills tasks that exceed
  a duration threshold. It does **not** enforce a hard timeout on EMR Serverless jobs (Spark
  needs its own configuration for that).
- **Cost tags.** Every resource is tagged with `project_name`, `domain_name`, `stage_name` —
  use AWS Cost Explorer or a FinOps tool to slice spend by domain or stage.
- **Athena cost.** Not capped by the framework. Set up AWS Budgets or Cost Anomaly Detection
  separately if `migrate_data` or ad-hoc queries on `prod` are a concern.
- **Concurrency.** Iceberg commit conflicts are retried up to 30× with 2–10-minute backoffs
  (set as table properties at creation). High-write-fan-in pipelines may still need tuning.
- **Region.** Single-region deployment by default (`eu-west-1`). Cross-region replication is
  not implemented.

## Common gotchas

- **EMR sandbox not enabled.** Deploying a pipeline with an `EMRServerless` task while the
  domain has `skip_emr_serverless_sandbox_creation = true` fails with a clear message. Flip
  the domain variable, re-apply the domain, then deploy the pipeline.
- **SDK version not bumped.** Editing `datalake_sdk/` without bumping the version in
  `pyproject.toml` produces a deployment that ships the old wheel. Always bump.
- **VPC tags missing.** The factories look up the VPC by `Name = {project}_network_platform_prod`
  and subnets by `Tier`. A misnamed VPC produces an opaque "data source returned no results"
  during `terraform plan`.
- **Network preconditions.** `domain_factory/network_validation.tf` asserts at plan time that
  the selected subnets exist and have a 0.0.0.0/0 route via an Internet Gateway (when
  `use_public_subnets = true`) or via a NAT Gateway (when `false`). A missing NAT or IGW
  produces an explicit error instead of an opaque ECS/EMR runtime failure.
- **Lake Formation admin needed at apply time.** The deploying principal must already be a
  Lake Formation admin in the account, otherwise the data-location registration step fails.
