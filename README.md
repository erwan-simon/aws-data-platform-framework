# AWS Data Platform Framework

* [I. Project Overview](#i-project-overview)
* [II. Architecture / Design](#ii-architecture--design)
* [III. Prerequisites](#iii-prerequisites)
* [IV. Installation / Setup](#iv-installation--setup)
  * [A. Install datalake\_sdk from AWS CodeArtifact](#a-install-datalake_sdk-from-aws-codeartifact)
  * [B. Install datalake\_sdk from Source](#b-install-datalake_sdk-from-source)
  * [C. Deploy Infrastructure](#c-deploy-infrastructure)
* [V. Usage](#v-usage)
  * [A. CLI - Ingest Data](#a-cli---ingest-data)
  * [B. Programmatic - Ingest Data with Python](#b-programmatic---ingest-data-with-python)
  * [C. Delete a Table](#c-delete-a-table)
  * [D. Migrate Data Across Stages](#d-migrate-data-across-stages)
  * [E. Query Data with Athena](#e-query-data-with-athena)
  * [F. AI Agent - Datalfred](#f-ai-agent---datalfred)
  * [G. Ingestion Modes](#g-ingestion-modes)
  * [H. Local Task Execution](#h-local-task-execution)
* [VI. Infrastructure](#vi-infrastructure)
  * [A. Domain Factory](#a-domain-factory)
  * [B. Pipeline Factory](#b-pipeline-factory)
  * [C. Terraform Modules](#c-terraform-modules)
  * [D. Deployment Workflow](#d-deployment-workflow)
* [VII. Configuration](#vii-configuration)
  * [A. Environment Variables](#a-environment-variables)
  * [B. Task Configuration](#b-task-configuration)
  * [C. Table Metadata](#c-table-metadata)
  * [D. Triggers](#d-triggers)
* [VIII. Project Structure](#viii-project-structure)
  * [A. datalake\_sdk](#a-datalake_sdk)
  * [B. domain\_factory](#b-domain_factory)
  * [C. pipeline\_factory](#c-pipeline_factory)
  * [D. test](#d-test)
* [IX. Limitations / Assumptions](#ix-limitations--assumptions)

## I. Project Overview

This project is an **AWS-based data lake platform** designed to facilitate data ingestion, storage, transformation, and governance at scale. It provides:

- A **Python SDK** (`datalake_sdk`) for interacting with the data lake, enabling data ingestion with multiple modes (overwrite, append, upsert)
- **Terraform infrastructure-as-code modules** for provisioning AWS resources organized into domains and pipelines
- Support for both **native Python (Pandas)** and **Spark (EMR Serverless)** processing environments
- **Apache Iceberg** table format for advanced data lake capabilities (ACID transactions, schema evolution, time travel)
- **AWS Lake Formation** integration for fine-grained access control and data governance
- An **AI agent** ("Datalfred") for natural language interaction with the data lake
- **Automated orchestration** using AWS Step Functions

The platform is intended for data engineers, data scientists, and developers who need to build scalable, governed data pipelines on AWS.

For detailed information about the `datalake_sdk` Python package, refer to the [datalake_sdk README](datalake_sdk/README.md).

## II. Architecture / Design

### High-Level Components

The architecture is organized around three main layers:

1. **SDK Layer** (`datalake_sdk`):
   - Python library providing abstractions for data ingestion and processing
   - CLI tool for manual data operations
   - Wrappers for Spark and native Python environments
   - AI agent (Datalfred) for conversational data lake interaction

2. **Infrastructure Layer** (Terraform modules):
   - **Domain Factory**: Provisions core AWS infrastructure per domain (S3 buckets, Glue databases, Lake Formation, Athena workgroups, IAM roles)
   - **Pipeline Factory**: Creates data pipelines with orchestrated tasks (ECS/EMR tasks, Step Functions, CloudWatch logs)
   
3. **Execution Layer**:
   - **ECS Fargate tasks**: Lightweight Python data processing
   - **EMR Serverless**: Spark-based distributed processing
   - **Step Functions**: Orchestration and workflow management

### Data Flow

1. Data is ingested via the `datalake_sdk` CLI or programmatically through Python code
2. Tasks run in containerized environments (ECS or EMR) defined by Terraform
3. Data is written to **S3** in Iceberg format with metadata in **AWS Glue Data Catalog**
4. **Lake Formation** manages permissions on databases and tables
5. **Athena** provides SQL query access to the data
6. **Step Functions** orchestrate multi-step pipelines with dependency management

### Key Design Patterns

- **Domain-Driven Design**: Resources are grouped by business domain
- **Infrastructure as Code**: All AWS resources defined in Terraform
- **Schema-on-Read**: Table schemas are inferred from data at ingestion time
- **Separation of Concerns**: Data storage (S3), metadata (Glue), access control (Lake Formation), and orchestration (Step Functions) are decoupled
- **Multi-Stage Support**: Terraform workspaces allow dev/uat/prod isolation

### Organizational Conventions

This platform adheres to organizational technical conventions:

- **CI/CD Platform**: GitLab CI is used for continuous integration and deployment (`.gitlab-ci.yml`). GitHub is a read-only mirror.
- **AWS Naming Convention**: Resources follow the pattern `{project_name}_{domain_name}_{stage_name}_resource_name`
- **Stage Name Derivation**: 
  - In GitLab CI: derived from Git branch name (`$CI_COMMIT_REF_SLUG`)
  - Locally: derived from active Terraform workspace
- **AWS Region**: Default region is `eu-west-1` (Ireland)
- **Terraform Backend**: Backend configuration is provided at initialization time via runtime parameters:
  ```bash
  terraform init \
    -backend-config="bucket=$TERRAFORM_BACKEND_BUCKET" \
    -backend-config="dynamodb_table=$TERRAFORM_BACKEND_DYNAMODB"
  ```
- **Cost Allocation Tags**: All resources are tagged with `project_name`, `domain_name`, and `stage_name` for FinOps tracking

## III. Prerequisites

### Required Tools

- **AWS Account** with administrative access or appropriate IAM permissions
- **Terraform** >= 5.60.0, < 6.14.0 (AWS provider version)
- **Python** ~3.13
- **Poetry** (for local SDK development and installation)
- **Docker** (for building container images and local task execution)
- **AWS CLI** configured with credentials
- **Git** access to the GitLab repository

### AWS Services Used

- **Storage & Catalog**: S3, Glue Data Catalog
- **Governance & Security**: Lake Formation, IAM
- **Compute**: ECS (Fargate), EMR Serverless
- **Orchestration**: Step Functions, EventBridge
- **Querying**: Athena
- **Monitoring**: CloudWatch
- **Container Registry**: ECR
- **AI/ML**: Bedrock (for Datalfred agent)
- **Package Management**: CodeArtifact
- **Notifications**: Secrets Manager (for Slack integration)

### Infrastructure Prerequisites

- **Terraform Backend**: S3 bucket and DynamoDB table for state storage (must be created beforehand)
- **VPC**: A VPC tagged with `Name: {project_name}_network_platform_prod` containing public and/or private subnets
- **NAT Gateway**: Required if using private subnets (`use_public_subnets=false`)

## IV. Installation / Setup

### A. Install datalake_sdk from AWS CodeArtifact

1. **Configure AWS credentials** with CodeArtifact read access:

```bash
export CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token \
  --domain $CODEARTIFACT_DOMAIN_NAME \
  --domain-owner $AWS_ACCOUNT_ID \
  --query authorizationToken \
  --output text)
```

2. **Configure pip** to use CodeArtifact:

```bash
pip config set site.index-url https://aws:$CODEARTIFACT_AUTH_TOKEN@$CODEARTIFACT_DOMAIN_NAME-$AWS_ACCOUNT_ID.d.codeartifact.$AWS_REGION.amazonaws.com/pypi/$CODEARTIFACT_REPOSITORY_NAME/simple/

pip config set site.extra-index-url https://pypi.python.org/simple/
```

3. **Install the SDK**:

```bash
pip install datalake-sdk
datalake_sdk --help
```

4. **(Optional) Install with AI agent support**:

```bash
pip install datalake-sdk[agent]
```

### B. Install datalake_sdk from Source

1. **Clone the repository**:

```bash
git clone ${REPO_URL}
cd datalake/datalake_sdk
```

2. **Install dependencies**:

```bash
poetry install
```

3. **Option 1 - Install globally**:

```bash
poetry build
pip install dist/*.whl
datalake_sdk --help
```

4. **Option 2 - Run via Poetry**:

```bash
poetry run datalake_sdk --help
```

For complete SDK documentation, see [datalake_sdk/README.md](datalake_sdk/README.md).

### C. Deploy Infrastructure

#### 1. Initialize Terraform Backend

Ensure you have an S3 bucket and DynamoDB table for Terraform state management.

#### 2. Create a Domain

Create a `main.tf` file using the `domain_factory` module:

```hcl
module "domain" {
  source                        = "./domain_factory"
  project_name                  = "my_project"
  domain_name                   = "my_domain"
  stage_name                    = "dev"
  git_repository                = "${REPO_URL}"
  datalake_admin_principal_arns = ["arn:aws:iam::123456789012:role/AdminRole"]
  failure_notification_receivers = ["user@example.com"]
}
```

#### 3. Deploy the Domain

```bash
terraform init \
  -backend-config="bucket=$TERRAFORM_BACKEND_BUCKET" \
  -backend-config="dynamodb_table=$TERRAFORM_BACKEND_DYNAMODB"

terraform workspace new dev
terraform apply
```

#### 4. Create Pipelines

Use the `pipeline_factory` module to create data pipelines (see [Section VI.B](#b-pipeline-factory) for configuration details).

## V. Usage

### A. CLI - Ingest Data

Ingest a CSV file into the data lake:

```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  ingest \
  --database-name my_database \
  --table-name my_table \
  --input-file-path ./file.csv \
  --ingestion-mode upsert \
  --upsert-keys "column_1/column_2" \
  --partition-keys "column_3/column_4" \
  --csv-delimiter ";"
```

**Note**: CSV files must include headers.

### B. Programmatic - Ingest Data with Python

```python
from datalake_sdk.native_python_processing_wrapper import NativePythonProcessingWrapper

wrapper = NativePythonProcessingWrapper(
    project_name="poc",
    domain_name="my_tests",
    stage_name="prd",
    output_tables={
        "my_database.my_table": {
            "upsert_keys": ["column_1", "column_2"],
            "partition_keys": ["column_3"],
            "ingestion_mode": "upsert"
        }
    }
)

dataframe = wrapper.read_input_dataset("./file.csv", csv_delimiter=";")
wrapper.ingest("my_database.my_table", dataframe)
```

For Spark environments, replace `NativePythonProcessingWrapper` with `SparkProcessingWrapper`.

### C. Delete a Table

```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  delete_table \
  --database-name my_database \
  --table-name my_table
```

### D. Migrate Data Across Stages

Copy the data of one or all tables from a source stage to the current target stage (e.g. `prod` → `dev`):

```bash
datalake_sdk \
  --project-name poc \
  --domain-name newsroom \
  --stage-name dev \
  migrate_data \
  --source-stage-name prod \
  --database-name newsroom \
  --source-table-name articles \
  --owner-job tests/test_native_write
```

Behavior:
- Reads the source via Athena in chunks and re-ingests through the SDK in `upsert` mode.
- If `--source-table-name` is omitted, every table of the source database is replicated to the target database with the same name.
- If `--upsert-keys` is omitted, falls back to the `datalake_sdk_upsert_keys` Glue table property of the source table.
- If `--owner-job pipeline_name/task_name` is provided, Lake Formation `ALL` permissions (with grant option) are granted on each target table to the IAM role `{project}_{domain}_{target_stage}_{pipeline}_{task}`. If omitted, the SDK falls back to the `datalake_sdk_pipeline_name` / `datalake_sdk_task_name` properties of the source table to derive the role; otherwise a warning is emitted (the migrating principal becomes the LF owner and the original pipeline may lose access).

### E. Query Data with Athena

Use the AWS Athena console or CLI to query Iceberg tables:

```sql
SELECT * FROM dev_my_database.my_table WHERE column_3 = 'value';
```

### F. AI Agent - Datalfred

Interact with the data lake using natural language (requires `datalake-sdk[agent]`):

```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  datalfred \
  --model-size large
```

Datalfred can:
- Query data using natural language
- Investigate pipeline failures
- Analyze code and configurations

For more information, see [datalake_sdk/README.md - Datalfred Agent](datalake_sdk/README.md#c-datalfred-agent).

### G. Ingestion Modes

- **overwrite**: Replaces all existing table data
- **append**: Adds new rows without modifying existing data (may create duplicates)
- **upsert**: Updates existing rows or inserts new ones based on upsert keys

For detailed explanations and examples, see [datalake_sdk/README.md - Ingestion Modes](datalake_sdk/README.md#viii-ingestion-modes).

### H. Local Task Execution

The platform allows you to execute task code in a local Dockerized environment that is **identical to the AWS task execution environment**. This is particularly useful for developing new tasks or debugging existing ones.

You can run either:
- **ECS tasks** (native Python with Pandas)
- **EMR Serverless tasks** (PySpark)

The Docker image can be:
- A **sandbox image** (intermediate base image)
- A **task-specific image** (containing the final Python/PySpark code)

#### Prerequisites

- Docker must be running locally
- The Docker image must be available:
  - If built locally, it's already available
  - If from ECR, you must authenticate and pull the image

#### 1. Authenticate to ECR

Assuming AWS credentials are configured:

```bash
aws ecr get-login-password --region ${ECR_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${ECR_REGION}.amazonaws.com
```

#### 2. Run an ECS Task (Native Python)

This launches a Jupyter Notebook environment for native Python tasks:

```bash
docker run \
  -e AWS_PROFILE=${AWS_CREDENTIALS_PROFILE} \
  --mount type=bind,source=$HOME/.aws/,target=/root/.aws/ \
  -p 8888:8888 \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${ECR_REGION}.amazonaws.com/${ECR_NAME}:${DOCKER_IMAGE_TAG} \
  jupyter notebook --ip="0.0.0.0" --no-browser --allow-root
```

The command will output the Jupyter Notebook URL. Copy and paste it into your browser.

#### 3. Run an EMR Serverless Task (PySpark)

This launches a Jupyter Notebook with PySpark configured:

```bash
export CREDENTIALS=$(aws configure export-credentials)
mkdir -p logs  # To access generated Spark logs

docker run -d \
  -e AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId') \
  -e AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey') \
  -e AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken // ""') \
  -e AWS_REGION=${AWS_REGION} \
  -e AWS_DEFAULT_REGION=${AWS_REGION} \
  --mount type=bind,source=$(pwd)/logs,target=/var/log/spark/user/ \
  -p 8888:8888 \
  -e PYSPARK_DRIVER_PYTHON=jupyter \
  -e PYSPARK_DRIVER_PYTHON_OPTS='notebook --ip="0.0.0.0" --no-browser' \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${ECR_REGION}.amazonaws.com/${ECR_NAME}:${DOCKER_IMAGE_TAG} \
  pyspark --master local \
  --conf spark.hadoop.fs.s3a.endpoint=s3.${AWS_REGION}.amazonaws.com \
  --conf spark.hadoop.hive.metastore.client.factory.class=com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory

cat logs/stderr
```

The Jupyter Notebook URL will be printed in the `logs/stderr` file. Copy and paste it into your browser.

#### Notes

- **AWS Credentials**: The ECS example mounts `~/.aws/` to use your local AWS profile. The EMR example exports credentials as environment variables.
- **Port Mapping**: Both examples expose port 8888 for Jupyter Notebook access.
- **Spark Configuration**: The EMR example configures Spark to use S3 and AWS Glue Data Catalog.
- **Logs Directory**: For EMR tasks, Spark logs are written to the local `logs/` directory for debugging.

## VI. Infrastructure

### A. Domain Factory

The `domain_factory` Terraform module provisions foundational infrastructure for a data domain.

#### Key Resources

- **S3 Buckets**:
  - `{project_name}-{domain_name}-{stage_name}-data`: Stores Iceberg table data with versioning and intelligent tiering
  - `{project_name}-{domain_name}-{stage_name}-technical`: Stores logs, temporary files, and Athena query results
  
- **Glue Database**: Domain-scoped catalog for tables (`{stage_prefix}{domain_name}`)

- **Lake Formation**: 
  - Registers S3 data location
  - Manages database and table permissions
  - Supports cross-account data sharing

- **Athena Workgroup**: Query execution environment (`{project_name}_{domain_name}_{stage_name}`)

- **IAM Roles**: Task execution roles with least-privilege permissions

- **Security Groups**: Network isolation for processing tasks

- **CodeArtifact Repository**: Private Python package hosting for the SDK

- **ECS/EMR Sandbox**: Pre-built base images for task execution

- **Lambda (Failsafe Shutdown)**: Monitors and terminates long-running tasks

- **Bedrock Inference Profile**: AI model access for Datalfred (model sizes: `small`, `medium`, `large`)

- **EMR Studio**: Interactive development environment for Spark jobs

#### Key Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `project_name` | string | Project identifier | Required |
| `domain_name` | string | Domain name | Required |
| `stage_name` | string | Environment (dev, uat, prod, etc.) | Required |
| `git_repository` | string | GitLab repository URL | Required |
| `datalake_admin_principal_arns` | list(string) | IAM principals with full data access | `[]` |
| `use_public_subnets` | bool | Use public vs. private subnets | `true` |
| `database_description` | string | Description of the domain database | `""` |
| `skip_emr_serverless_sandbox_creation` | bool | Skip EMR sandbox image creation. Must be `false` if any pipeline of this domain uses an `EMRServerless` task | `true` |
| `failure_notification_receivers` | list(string) | Email addresses for failure alerts | Required |

#### Outputs

The module exports a domain object containing all necessary information for pipeline creation (see `domain_factory/outputs.tf`).

### B. Pipeline Factory

The `pipeline_factory` Terraform module provisions data pipelines with orchestrated tasks.

#### Key Resources

- **Step Functions State Machine**: Workflow orchestration with task dependencies

- **ECS or EMR Tasks**: Containerized data processing
  - **ECS**: Fargate tasks for lightweight Python jobs
  - **EMR**: Serverless Spark for large-scale processing

- **Glue Database** (optional): Pipeline-scoped catalog (`{stage_prefix}{pipeline_name}`)

- **CloudWatch Logs**: Task execution logs with 30-day retention

- **EventBridge Scheduler**: Schedule-based or event-driven triggers

- **IAM Roles**: Task-specific permissions (data access, Lake Formation, S3)

- **ECR Repositories**: Docker image storage per task

- **Failure Notifications**: CloudWatch Events trigger notifications on task failures

#### Key Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `pipeline_name` | string | Pipeline identifier | Required |
| `tasks_configuration` | map(object) | Task definitions (see below) | Required |
| `trigger` | object | Pipeline trigger configuration | `{"type": "none", "argument": "none"}` |
| `orchestration_configuration_template_file_path` | string | Step Functions template path | Required |
| `domain_object` | object | Output from domain_factory | Required |
| `failure_notification_receivers` | list(string) | Email addresses for failure alerts | `[]` |
| `skip_pipeline_database_creation` | bool | Skip pipeline database creation | `false` |

#### Task Configuration Structure

```hcl
tasks_configuration = {
  "task_name" : {
    "type" : "python" | "sql"
    "path" : "./relative/path/to/task/code"
    "infra_type" : "ECS" | "EMRServerless"   # EMRServerless requires the domain to be deployed with skip_emr_serverless_sandbox_creation = false
    "infra_config" : {
      "cpu" : "512"        # ECS only: CPU units
      "memory" : "1024"    # ECS only: Memory in MB
    }
    "input_tables" : ["db.table1", "db.table2"]
    "output_tables" : {
      "db.output_table" : {
        "ingestion_mode" : "overwrite" | "append" | "upsert"
        "upsert_keys" : ["id"]
        "partition_keys" : ["date"]
      }
    }
    "additional_parameters" : {
      "param_key" : "static_value"
      "dynamic_param.$" : "$.trigger_param"  # Reference trigger input
    }
    "additional_rebuild_trigger" : {}  # Force image rebuild
    "additional_permissions" : "<IAM policy JSON>"  # Extra IAM permissions
  }
}
```

#### Trigger Configuration

**Schedule-based (cron)**:
```hcl
trigger = {
  "type" : "schedule"
  "argument" : "cron(15 1 * * ? *)"
  "parameters" : jsonencode({
    "key" : "value"
  })
}
```

**Manual execution only**:
```hcl
trigger = {
  "type" : "none"
  "argument" : "none"
}
```

### C. Terraform Modules

The `pipeline_factory/modules` directory contains three submodules:

#### 1. `ecs_factory`

Provisions ECS Fargate tasks:
- Task definition with environment variables
- IAM roles for task execution and data access
- ECR repository and Docker image build
- CloudWatch log groups

#### 2. `emr_factory`

Provisions EMR Serverless applications:
- EMR application with Spark runtime
- IAM roles for job execution and data access
- ECR repository and Docker image build (Spark-compatible)
- S3 paths for Spark logs

#### 3. `build_and_upload_image_to_ecr`

Automates Docker image management:
- Copies task code and dependencies
- Builds Docker image using sandbox base image
- Pushes image to ECR
- Supports rebuild triggers for code changes

### D. Deployment Workflow

1. **Domain Deployment**: Terraform provisions domain infrastructure (S3, Glue, Lake Formation, IAM, etc.)

2. **Pipeline Deployment**: Terraform provisions pipeline infrastructure
   - Creates Step Functions state machine
   - Builds Docker images for each task
   - Pushes images to ECR
   - Creates ECS task definitions or EMR applications

3. **Task Execution**:
   - EventBridge scheduler or manual trigger starts Step Functions execution
   - Step Functions orchestrates task execution based on orchestration template
   - ECS/EMR tasks run with environment variables set by Terraform
   - Tasks use `datalake_sdk` to read/write data

4. **Data Ingestion**:
   - Tasks transform data using Pandas or Spark
   - SDK ingests data to S3 in Iceberg format
   - Glue Catalog metadata is updated
   - Lake Formation permissions are enforced

5. **Monitoring & Notifications**:
   - CloudWatch logs capture task execution
   - Failsafe Lambda monitors task duration
   - CloudWatch Events trigger email notifications on failures

## VII. Configuration

### A. Environment Variables

Set automatically by infrastructure; users can access via `task_additional_parameters`:

| Variable | Description | Set By |
|----------|-------------|--------|
| `PROJECT_NAME` | Project identifier | Terraform |
| `DOMAIN_NAME` | Domain name | Terraform |
| `STAGE_NAME` | Environment name | Terraform |
| `PIPELINE_NAME` | Pipeline name | Terraform |
| `TASK_NAME` | Task name | Terraform |
| `INPUT_TABLES` | JSON-encoded list of input tables | Terraform |
| `OUTPUT_TABLES` | JSON-encoded dict of output table configs | Terraform |
| `IS_SQL_JOB` | Whether task executes SQL (`true`/`false`) | Terraform |
| `TASK_ADDITIONAL_PARAMETERS_*` | Custom parameters from Terraform | Terraform |
| `step_function_task_token` | Step Functions callback token | Step Functions |
| `step_function_execution_arn` | Step Functions execution ARN | Step Functions |

### B. Task Configuration

Example task configuration in Terraform:

```hcl
tasks_configuration = {
  "my_task" : {
    "type" : "python",
    "path" : "./my_task/",
    "infra_type" : "ECS",
    "infra_config" : {
      "cpu" : "512",
      "memory" : "1024"
    },
    "input_tables" : ["db.input_table"],
    "output_tables" : {
      "db.output_table" : {
        "ingestion_mode" : "upsert",
        "upsert_keys" : ["id"],
        "partition_keys" : ["date"]
      }
    },
    "additional_parameters" : {
      "my_param.$" : "$.trigger_param",  # Dynamic from trigger
      "static_param" : "value"
    },
    "additional_permissions" : data.aws_iam_policy_document.my_policy.json
  }
}
```

### C. Table Metadata

Place YAML files in `code/tables_configuration/` to document tables:

```yaml
# code/tables_configuration/my_database.my_table.yaml
description: "Customer dimension table"
schema:
  customer_id:
    description: "Unique customer identifier"
  customer_name:
    description: "Full name of the customer"
```

In addition, the SDK automatically writes a few Glue **table properties** on every successful ingestion:

- `datalake_sdk_upsert_keys` — comma-separated upsert keys used (only for `upsert` mode). Updated at every write; a warning is emitted if the keys differ from the previously stored value.
- `datalake_sdk_pipeline_name` / `datalake_sdk_task_name` — the pipeline/task that produced the table (skipped for ad-hoc CLI ingestions).

These properties are consumed by `datalake_sdk migrate_data` to derive default upsert keys and the owner IAM role.

### D. Triggers

**Schedule**: Cron-based execution

```hcl
trigger = {
  "type" : "schedule"
  "argument" : "cron(15 1 * * ? *)"
  "parameters" : jsonencode({"key": "value"})
}
```

**None**: Manual execution only

```hcl
trigger = {
  "type" : "none"
  "argument" : "none"
}
```

## VIII. Project Structure

```
datalake/
├── datalake_sdk/              # Python SDK and CLI
├── domain_factory/            # Terraform module for domain infrastructure
├── pipeline_factory/          # Terraform module for pipeline infrastructure
│   └── modules/
│       ├── ecs_factory/       # ECS task provisioning
│       ├── emr_factory/       # EMR Serverless provisioning
│       └── build_and_upload_image_to_ecr/  # Docker build and push
├── test/                      # Integration tests and examples
├── doc_resources/             # Documentation resources
├── .gitlab-ci.yml             # GitLab CI pipeline configuration
├── .github/workflows/         # GitHub Actions (semantic-release)
├── LICENSE                    # Creative Commons Attribution-NonCommercial 4.0
└── README.md                  # This file
```

### A. datalake_sdk

**Purpose**: Provides a unified interface for data lake operations.

The `datalake_sdk` is a comprehensive Python package for interacting with the data lake. It includes:

- **CLI**: Command-line interface for ingestion, table deletion, and AI agent interaction
- **Processing Wrappers**: Abstract base class and implementations for Pandas and Spark
- **Datalfred Agent**: AI-powered assistant for natural language data lake interaction

For complete documentation, see [datalake_sdk/README.md](datalake_sdk/README.md).

**Key Files**:
- `main.py`: CLI entry point with subcommands
- `base_processing_wrapper.py`: Abstract base class
- `native_python_processing_wrapper.py`: Pandas implementation
- `spark_processing_wrapper.py`: Spark implementation
- `ingestion.py`: CLI ingestion command
- `delete_table.py`: CLI delete command
- `migrate_data.py`: CLI command to copy data from one stage to another
- `update_foreign_linked_databases.py`: CLI command to sync Glue resource links for cross-account databases
- `datalfred_agent/`: AI agent modules

**Dependencies** (from `pyproject.toml`):
- Core: `boto3`, `click`, `awswrangler`, `pyyaml`, `tqdm`, `slack-sdk`
- Optional: `strands-agents`, `strands-agents-tools`, `strands-agents-builder` (for Datalfred)

**Version**: 5.7.11 (automatically detected by domain_factory)

### B. domain_factory

**Purpose**: Terraform module to provision AWS resources for a data domain.

**Key Files**:
- `s3_data.tf`, `s3_technical.tf`: S3 bucket definitions
- `glue_database.tf`: Glue Data Catalog database
- `lakeformation.tf`: Lake Formation registration and permissions
- `athena_workgroup.tf`: Athena workgroup configuration
- `ecs_cluster_sandbox.tf`: ECS base image and cluster
- `emr_serverless_application_sandbox.tf`: EMR Serverless base image
- `codeartifact_repository.tf`: Private package repository
- `lambda_failsafe_shutdown.tf`: Task timeout enforcement
- `bedrock_inference_profile.tf`: AI model access
- `code_datalake_sdk.tf`: Packages and publishes SDK to CodeArtifact
- `variables.tf`: Input variables
- `outputs.tf`: Exported domain configuration
- `locals.tf`: Local variables (environment naming, SDK version extraction)

**Outputs**: Exports domain configuration consumed by pipeline_factory.

### C. pipeline_factory

**Purpose**: Terraform module to create data pipelines with orchestrated tasks.

**Key Files**:
- `step_function.tf`: AWS Step Functions state machine
- `ecs_tasks.tf`: ECS task module invocations
- `emr_tasks.tf`: EMR Serverless application module invocations
- `event_bridge_scheduler.tf`: Pipeline trigger configuration
- `cloudwatch_event_task_failed.tf`: Failure notification setup
- `cloudwatch_event_failsafe_shutdown.tf`: Failsafe Lambda trigger
- `glue_database.tf`: Pipeline-scoped database (optional)
- `variables.tf`: Input variables
- `outputs.tf`: Pipeline outputs
- `locals.tf`: Local variables (environment naming)

**Modules**:
- `ecs_factory/`: Provisions ECS Fargate tasks
- `emr_factory/`: Provisions EMR Serverless applications
- `build_and_upload_image_to_ecr/`: Builds and uploads Docker images

### D. test

**Purpose**: Integration tests and example pipeline implementation.

**Key Files**:
- `domain.tf`: Test domain deployment
- `pipeline.tf`: Test pipeline with multiple task types
- `variables.tf`: Test-specific variable definitions
- `integration_tests_pipeline/`: Test tasks
  - `test_write/`: Python task for data generation
  - `test_native_sql_entrypoint/`: Native SQL task
  - `test_spark_sql_entrypoint/`: Spark SQL task
  - `check_and_clean/`: Validation and cleanup task
  - `orchestration_configuration.tftpl.json`: Step Functions orchestration
- `utils/`: Test utilities
  - `run_integration_tests.py`: Test execution script
  - `pipeline_utils/`: Test library for dependency validation

**Variable Handling**:

The test configuration uses a different variable format for convenience:

| Variable | Type in domain_factory | Type in test | Transformation |
|----------|----------------------|--------------|----------------|
| `datalake_admin_principal_arns` | `list(string)` | `string` (comma-separated role names) | Split by comma, lookup ARNs via `data.aws_iam_role`, pass as list |
| `failure_notification_receivers` | `list(string)` | `string` (comma-separated emails) | Split by comma in module call |

Example test variable usage:
```hcl
# test/domain.tf
data "aws_iam_role" "datalake_admins" {
  for_each = toset(split(",", var.datalake_admin_principal_arns))
  name = each.value
}

module "domain" {
  # ...
  datalake_admin_principal_arns = values(data.aws_iam_role.datalake_admins)[*].arn
  failure_notification_receivers = split(",", var.failure_notification_receivers)
}
```

**CI/CD**: Integration tests run automatically in GitLab CI (`run_integration_tests` stage).

## IX. Limitations / Assumptions

1. **AWS-Only**: This platform is tightly coupled to AWS services and cannot be deployed on other cloud providers without significant refactoring.

2. **Python 3.13**: The SDK and processing tasks require Python ~3.13. Older Python versions are not supported.

3. **Iceberg Format**: All tables are stored in Apache Iceberg format. Direct Parquet or other formats are not supported for managed tables.

4. **Region**: Infrastructure is deployed in a single AWS region (default: `eu-west-1`). Cross-region replication is not implemented.

5. **Terraform State Backend**: Assumes an existing S3 bucket and DynamoDB table for Terraform state management. These must be created manually before deployment.

6. **Naming Conventions**: Resource names follow the pattern `{project_name}_{domain_name}_{stage_name}`. Non-prod stages prefix database names (e.g., `dev_my_database`). Production (`stage_name = "prod"`) databases have no prefix.

7. **Lake Formation Permissions**: The platform assumes AWS Lake Formation is the primary access control mechanism. IAM-only setups are not fully supported.

8. **CSV Ingestion**: CSV files must include headers for schema inference.

9. **Upsert Key Uniqueness**: Upsert keys must guarantee row uniqueness in the ingested dataset. Violations will cause ingestion failure.

10. **Concurrency**: Iceberg commit conflicts (e.g., simultaneous writes) are mitigated with retries (up to 30 retries with 2-10 minute waits), but high-concurrency scenarios may require tuning.

11. **Failsafe Shutdown**: The failsafe Lambda function monitors task durations but does not enforce hard limits on EMR Serverless jobs.

12. **Datalfred Agent**: The AI agent requires AWS Bedrock inference profiles to be pre-configured in the domain. Model sizes are fixed (`small`, `medium`, `large`).

13. **GitLab Primary**: GitLab is the source of truth for CI/CD. GitHub is a read-only mirror. GitHub Actions are only used for semantic-release on the `prod` branch.

14. **Subnet Configuration**: Tasks run in public subnets by default (`use_public_subnets=true`). Private subnets require a NAT Gateway for internet access (not provisioned by this platform).

15. **Integration Tests**: The `test/` folder contains integration tests that create and delete tables. These tests assume administrative permissions and should not be run in production environments.

16. **ECS Task Limits**: ECS tasks are constrained by Fargate CPU/memory limits (max 4 vCPU, 30 GB RAM). Larger workloads require EMR Serverless.

17. **SQL Tasks**: SQL entry point tasks (`type: "sql"`) are limited to single output tables and use a `main.sql` file. Multi-table SQL tasks are not supported.

18. **Workspace Isolation**: Terraform workspaces are used for environment isolation. The stage name is derived from:
    - **GitLab CI**: Git branch name (`$CI_COMMIT_REF_SLUG`)
    - **Local execution**: Active Terraform workspace (use `terraform workspace select <stage>`)

19. **Athena Costs**: Query costs are not monitored or capped by the platform. Users should implement AWS Budgets or Cost Anomaly Detection separately.

20. **VPC Dependency**: The domain factory expects a VPC tagged with `Name: {project_name}_network_platform_prod` containing appropriately tagged subnets (`Tier: Public` or `Tier: Private`).

21. **EMR Sandbox Creation**: By default, `skip_emr_serverless_sandbox_creation=true` to reduce deployment time. You **must** set it to `false` on the domain before deploying any pipeline that contains an `EMRServerless` task — pipelines build their EMR task images on top of the domain's EMR sandbox image, so without it the pipeline deployment will fail.

22. **CodeArtifact Publishing**: The domain factory automatically builds and publishes the `datalake_sdk` to CodeArtifact during deployment. The version is extracted from `datalake_sdk/pyproject.toml`.

23. **Semantic Versioning**: Releases are managed via semantic-release on GitHub (`.releaserc.json`). Conventional commit messages are required for automated versioning.

24. **Local AWS Credentials**: Terraform executed locally uses the default AWS credentials configured on the machine. Verify the active AWS account before applying changes.

25. **Local Task Execution**: Docker must be running and the task image must be available locally (either built locally or pulled from ECR after authentication). AWS credentials are required for accessing S3 and Glue.
