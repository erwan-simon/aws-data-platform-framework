# Datalake SDK

* [I. Project Overview](#i-project-overview)
* [II. Architecture / Design](#ii-architecture--design)
* [III. Prerequisites](#iii-prerequisites)
* [IV. Installation / Setup](#iv-installation--setup)
  * [A. Install from AWS CodeArtifact PyPI Repository](#a-install-from-aws-codeartifact-pypi-repository)
  * [B. Install from Source Repository](#b-install-from-source-repository)
* [V. Usage](#v-usage)
  * [A. CLI Usage](#a-cli-usage)
  * [B. Python Library Usage](#b-python-library-usage)
  * [C. Datalfred Agent](#c-datalfred-agent)
* [VI. Configuration](#vi-configuration)
* [VII. Project Structure](#vii-project-structure)
  * [A. Core Modules](#a-core-modules)
  * [B. Processing Wrappers](#b-processing-wrappers)
  * [C. Datalfred Agent](#c-datalfred-agent-1)
* [VIII. Ingestion Modes](#viii-ingestion-modes)
  * [A. Overwrite](#a-overwrite)
  * [B. Append](#b-append)
  * [C. Upsert](#c-upsert)
* [IX. Apache Iceberg Integration](#ix-apache-iceberg-integration)
* [X. Limitations / Assumptions](#x-limitations--assumptions)

## I. Project Overview

The **Datalake SDK** is a Python toolkit for interacting with an AWS-based data lake infrastructure. It provides both a command-line interface (CLI) and a programmatic API for data ingestion, table management, and data operations on Apache Iceberg tables stored in AWS S3 and cataloged in AWS Glue Data Catalog.

**Key capabilities:**
- **Data ingestion** with multiple ingestion modes (overwrite, append, upsert)
- **Table deletion** with associated data cleanup
- **Lake Formation integration** for cross-account data sharing
- **AI-powered agent** (Datalfred) for querying data and orchestrating operations
- **Dual execution modes**: Native Python (Pandas) or Spark

The SDK is designed for data engineers, data analysts, and developers who need to programmatically interact with a data lake following organizational AWS conventions.

## II. Architecture / Design

The Datalake SDK follows a modular architecture with the following key components:

### High-Level Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Datalake SDK                            │
├──────────────────────────────────────────────────────────────┤
│  CLI Entry Point (main.py)                                   │
│  ├─ ingest                                                    │
│  ├─ delete_table                                              │
│  ├─ update_foreign_linked_databases                          │
│  └─ datalfred (optional, requires strands-agents)            │
├──────────────────────────────────────────────────────────────┤
│  Processing Wrappers                                          │
│  ├─ BaseProcessingWrapper (abstract)                         │
│  ├─ NativePythonProcessingWrapper (Pandas + awswrangler)     │
│  └─ SparkProcessingWrapper (PySpark)                         │
├──────────────────────────────────────────────────────────────┤
│  Datalfred Agent (AI Assistant)                              │
│  ├─ Main orchestrator                                        │
│  ├─ Data Analyst (queries data)                              │
│  ├─ Code Debugger (analyzes code)                            │
│  └─ Run Guy (executes tasks)                                 │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│                    AWS Services                              │
│  ├─ AWS Glue Data Catalog (metadata)                         │
│  ├─ AWS S3 (data storage)                                    │
│  ├─ AWS Athena (querying)                                    │
│  ├─ AWS Lake Formation (access control)                      │
│  └─ AWS Bedrock (AI models for Datalfred)                    │
└──────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Naming Convention**: Resources follow the organizational pattern `{project_name}_{domain_name}_{stage_name}_resource_name`
2. **Dual Processing Modes**: Supports both Pandas-based (lightweight) and Spark-based (distributed) processing
3. **Schema-on-Read**: CSV files must include headers; schema is inferred during ingestion
4. **Iceberg Format**: All tables use Apache Iceberg format version 2 for ACID transactions and schema evolution
5. **Environment Awareness**: Stage names determine the database prefix (e.g., `dev_`, `prod` has no prefix)
6. **Automatic Maintenance**: Iceberg table maintenance (VACUUM, OPTIMIZE) runs automatically every 10 table versions

## III. Prerequisites

### Required Tools & Environments
- **Python**: Version ~3.13 (as specified in pyproject.toml)
- **Poetry**: For dependency management (optional, only for source installation)
- **AWS CLI**: Configured with appropriate credentials
- **AWS Account**: With permissions for:
  - AWS Glue (Data Catalog operations)
  - AWS S3 (data bucket access)
  - AWS Athena (query execution)
  - AWS Step Functions (optional, for orchestration)
  - AWS Lake Formation (optional, for cross-account sharing)
  - AWS Bedrock (optional, for Datalfred agent)
  - AWS CodeArtifact (optional, for package repository access)

### AWS Permissions
- **Read/Write** access to S3 data buckets
- **Full access** to Glue Data Catalog databases and tables
- **Execute** permissions for Athena queries in designated workgroups
- **AWSCodeArtifactReadOnlyAccess** (for CodeArtifact installation method)

### AWS Region
- Default region: **eu-west-1** (Ireland)
- Can be overridden via boto3 session configuration

## IV. Installation / Setup

You can install the Datalake SDK using two methods: from AWS CodeArtifact or from source.

### A. Install from AWS CodeArtifact PyPI Repository

This method requires AWS credentials with CodeArtifact read access (see [AWSCodeArtifactReadOnlyAccess managed policy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AWSCodeArtifactReadOnlyAccess.html)).

1. **Configure pip to use AWS CodeArtifact**:

```bash
export CODEARTIFACT_AUTH_TOKEN=`aws codeartifact get-authorization-token \
  --domain $CODEARTIFACT_DOMAIN_NAME \
  --domain-owner $AWS_ACCOUNT_ID \
  --query authorizationToken \
  --output text`

pip config set site.index-url https://aws:$CODEARTIFACT_AUTH_TOKEN@$CODEARTIFACT_DOMAIN_NAME-$AWS_ACCOUNT_ID.d.codeartifact.eu-west-1.amazonaws.com/pypi/$CODEARTIFACT_REPOSITORY_NAME/simple/

# Add public PyPI as fallback for dependencies
pip config set site.extra-index-url https://pypi.python.org/simple/
```

2. **Install the package**:

```bash
pip install datalake-sdk
datalake_sdk --help
```

**Note**: This configuration affects all pip installations in your environment. To reset, delete the [pip config file](https://pip.pypa.io/en/stable/topics/configuration/).

### B. Install from Source Repository

1. **Clone the repository** (requires GitLab access):

```bash
git clone ${REPO_URL}
cd datalake/datalake_sdk
```

2. **Install dependencies using Poetry**:

```bash
poetry install
```

3. **Choose an execution method**:

   **Option 1: Install as a system-wide package**:
   ```bash
   poetry build
   pip install dist/*.whl
   datalake_sdk --help
   ```
   This allows `datalake_sdk` to be called from anywhere. Requires reinstallation after code changes.

   **Option 2: Run within Poetry's virtual environment**:
   ```bash
   poetry run datalake_sdk --help
   ```
   This method does NOT require reinstallation after code changes but is only available within the project directory.

### Installing Optional Features

The Datalfred AI agent requires additional dependencies:

```bash
# Using pip
pip install datalake-sdk[agent]

# Using poetry
poetry install --extras agent
```

## V. Usage

The Datalake SDK provides three primary interfaces: CLI commands, Python library API, and the Datalfred AI agent.

### A. CLI Usage

All CLI commands require three global parameters:
- `--project-name` / `-p`: Project identifier (e.g., company name)
- `--domain-name` / `-d`: Functional/product domain
- `--stage-name` / `-s`: Environment name (dev, prod, etc.)

**View all commands**:
```bash
datalake_sdk --help
```

#### 1. Data Ingestion

**Basic CSV ingestion**:
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

**Parquet ingestion**:
```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  ingest \
    --database-name my_database \
    --table-name my_table \
    --input-file-path s3://bucket/path/to/file.parquet \
    --ingestion-mode append
```

**Using Spark for large datasets**:
```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  ingest \
    --database-name my_database \
    --table-name my_table \
    --input-file-path s3://bucket/large-dataset/ \
    --ingestion-mode overwrite \
    --use-spark
```

**Important**: CSV files MUST contain headers, as the SDK uses a schema-on-read pattern.

#### 2. Table Deletion

Deletes both the Glue table metadata and all associated S3 data:

```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  delete_table \
    --database-name my_database \
    --table-name my_table
```

A confirmation prompt will appear before deletion.

#### 3. Update Foreign Linked Databases

Synchronizes Lake Formation resource links for cross-account data sharing:

```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  update_foreign_linked_databases
```

This command:
- Creates resource links for databases shared from other AWS accounts
- Removes orphaned resource links pointing to deleted resources

### B. Python Library Usage

The SDK can be used programmatically in both native Python and Spark environments.

#### 1. Native Python (Pandas) Example

```python
from datalake_sdk.native_python_processing_wrapper import NativePythonProcessingWrapper

# Initialize wrapper
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

# Read input data
input_df = wrapper.read_input_dataset("./file.csv", csv_delimiter=";")

# Ingest data
wrapper.ingest("my_database.my_table", input_df)
```

#### 2. Spark Example

```python
from datalake_sdk.spark_processing_wrapper import SparkProcessingWrapper

# Initialize wrapper
wrapper = SparkProcessingWrapper(
    project_name="poc",
    domain_name="my_tests",
    stage_name="prd",
    output_tables={
        "my_database.my_table": {
            "upsert_keys": [],
            "partition_keys": ["year", "month"],
            "ingestion_mode": "append"
        }
    }
)

# Read input data
input_df = wrapper.read_input_dataset("s3://bucket/path/data.parquet")

# Ingest data
wrapper.ingest("my_database.my_table", input_df)
```

#### 3. Custom Processing Function

For complex ETL workflows, extend the wrapper:

```python
from datalake_sdk.native_python_processing_wrapper import NativePythonProcessingWrapper

class MyCustomProcessor(NativePythonProcessingWrapper):
    def processing_function(self):
        # Read from input table
        df = self.read_input_dataset("s3://bucket/input.csv")
        
        # Perform transformations
        df_transformed = df[df['value'] > 100]
        
        # Return results
        return {
            "output_db.output_table": self.ProcessingResponse(
                dataframe=df_transformed,
                job_end_status=self.JobEndStatus.SUCCESS,
                job_end_message="Processing completed successfully"
            )
        }

# Execute
processor = MyCustomProcessor(output_tables={...})
processor.execute()
```

### C. Datalfred Agent

Datalfred is an AI-powered assistant for interacting with the data lake using natural language.

**Requirements**: Install with `[agent]` extra (requires AWS Bedrock access and inference profiles).

#### Interactive Mode

```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  datalfred \
    --model-size large
```

This opens an interactive session. Type your questions and commands in natural language:
```
>>> What databases are available?
>>> Show me the schema for the users table
>>> Run an ingestion for the latest sales data
>>> exit
```

#### One-Shot Query

```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  datalfred \
    --model-size small \
    --user-prompt "List all tables in the analytics database"
```

#### Session Persistence

Resume a previous conversation:

```bash
datalake_sdk \
  --project-name poc \
  --domain-name my_tests \
  --stage-name prd \
  datalfred \
    --session-id my-session-123 \
    --model-size medium
```

**Model Sizes**: `small`, `medium`, `large` (affects cost and capability)

**Sub-agents**:
- **Data Analyst**: Queries databases, lists schemas, executes Athena queries
- **Code Debugger**: Analyzes pipeline code and configurations
- **Run Guy**: Executes ingestions and data operations

## VI. Configuration

### Environment Variables

The SDK relies on the following environment variables (set automatically by CLI or required for library usage):

| Variable | Description | Required |
|----------|-------------|----------|
| `PROJECT_NAME` | Project identifier | Yes |
| `DOMAIN_NAME` | Domain/product name | Yes |
| `STAGE_NAME` | Environment (dev, prod, etc.) | Yes |
| `PIPELINE_NAME` | Pipeline identifier | No |
| `TASK_NAME` | Task identifier | No |
| `IS_SQL_JOB` | Whether task uses SQL (`true`/`false`) | No |
| `INPUT_TABLES` | JSON list of input tables | No |
| `OUTPUT_TABLES` | JSON dict of output table configurations | No |
| `step_function_task_token` | AWS Step Functions task token | No |
| `step_function_execution_arn` | Step Functions execution ARN | No |

### AWS Resource Naming

Resources are named according to organizational conventions:

```
{project_name}_{domain_name}_{stage_name}_resource_name
```

**Examples**:
- S3 Data Bucket: `poc-my-tests-prd-data` (underscores become hyphens)
- S3 Technical Bucket: `poc-my-tests-prd-technical`
- Athena Workgroup: `poc_my_tests_prd`
- Database Name (prod): `my_database`
- Database Name (dev): `dev_my_database`

**Note**: Production (`stage_name = prod`) databases do NOT have the stage prefix.

### Ingestion Parameters

When configuring `output_tables` for ingestion:

```python
output_tables = {
    "database_name.table_name": {
        "ingestion_mode": "upsert",           # Required: overwrite, append, or upsert
        "upsert_keys": ["id", "timestamp"],   # Required for upsert mode
        "partition_keys": ["year", "month"],  # Optional: Iceberg partitioning
        "table_configuration": {              # Optional: metadata
            "description": "Table description",
            "schema": {
                "column_name": {"description": "Column description"}
            }
        }
    }
}
```

### Iceberg Table Properties

Tables are automatically created with the following Iceberg properties:
- `format-version`: 2 (Athena-compatible)
- `commit.retry.num-retries`: 30
- `commit.retry.min-wait-ms`: 120000 (2 minutes)
- `commit.retry.max-wait-ms`: 600000 (10 minutes)

## VII. Project Structure

```
datalake_sdk/
├── datalake_sdk/              # Main package
│   ├── main.py                # CLI entry point
│   ├── ingestion.py           # Ingestion CLI command
│   ├── delete_table.py        # Table deletion CLI command
│   ├── update_foreign_linked_databases.py  # Lake Formation sync
│   ├── base_processing_wrapper.py          # Abstract base class
│   ├── native_python_processing_wrapper.py # Pandas implementation
│   ├── spark_processing_wrapper.py         # Spark implementation
│   ├── slack.py               # Slack notification helper
│   ├── tqdm_logging_handler.py # Logging handler
│   └── datalfred_agent/       # AI agent module
│       ├── main.py            # Agent orchestrator
│       ├── data_analyst.py    # Data querying sub-agent
│       ├── code_debugger.py   # Code analysis sub-agent
│       └── run_guy.py         # Execution sub-agent
├── dist/                      # Build artifacts (ignored by git)
├── datalfred_outputs/         # Agent output directory
├── pyproject.toml             # Poetry configuration
├── poetry.lock                # Dependency lock file
└── README.md                  # This file
```

### A. Core Modules

- **`main.py`**: CLI entry point using Click framework; registers all subcommands
- **`ingestion.py`**: Implements the `ingest` CLI command with file reading and ingestion orchestration
- **`delete_table.py`**: Implements table deletion with S3 object cleanup and Glue table removal
- **`update_foreign_linked_databases.py`**: Manages Lake Formation resource links for cross-account access

### B. Processing Wrappers

**`base_processing_wrapper.py`**
- Abstract base class for both Spark and native Python implementations
- Provides common functionality:
  - Environment setup and configuration loading
  - Table existence checks
  - Metadata updates
  - Iceberg table maintenance (VACUUM, OPTIMIZE)
  - Step Functions integration for orchestration
  - Processing response handling

**`native_python_processing_wrapper.py`**
- Pandas-based implementation using `awswrangler`
- Suitable for small to medium datasets
- Features:
  - CSV, Parquet, and JSON reading from local or S3
  - Automatic partition splitting to avoid Athena limits
  - Retry logic for Iceberg commit conflicts
  - Supports all ingestion modes

**`spark_processing_wrapper.py`**
- PySpark-based implementation for distributed processing
- Suitable for large datasets
- Features:
  - Iceberg Spark integration via Glue Catalog
  - Dynamic partition overwrite mode
  - SQL-based ingestion operations
  - Supports all ingestion modes

### C. Datalfred Agent

The agent system uses the `strands-agents` framework (optional dependency):

- **`main.py`**: Orchestrates agent workflow, manages sessions, calculates costs
- **`data_analyst.py`**: Tools for listing databases, tables, executing Athena queries
- **`code_debugger.py`**: Analyzes pipeline code and debugging information
- **`run_guy.py`**: Executes ingestions and data operations

**Session Management**:
- Local sessions: Stored temporarily using `FileSessionManager`
- Persistent sessions: Stored in S3 using `S3SessionManager`

**Cost Tracking**: Automatically calculates token usage and cost based on model size.

## VIII. Ingestion Modes

The SDK supports three ingestion modes, applicable to both Spark and native Python execution.

### A. Overwrite

Replaces all existing table data with the new dataset.

**Example**:

| Before Ingestion | Ingested Data | After Ingestion |
|------------------|---------------|-----------------|
| toto / 1 / 123   | toto / 3 / 28932 | toto / 3 / 28932 |
| tata / 2 / 9823  |                  |                  |

**Use Case**: Full table refresh, daily snapshots

### B. Append

Adds new rows to the table without modifying existing data.

**Example**:

| Before Ingestion | Ingested Data | After Ingestion |
|------------------|---------------|-----------------|
| toto / 1 / 123   | toto / 3 / 28932 | toto / 1 / 123 |
| tata / 2 / 9823  | tata / 2 / 9823  | tata / 2 / 9823 |
|                  |                  | toto / 3 / 28932 |
|                  |                  | tata / 2 / 9823 |

**Warning**: Can create duplicate rows. Use `upsert` mode to avoid duplicates.

**Use Case**: Event logs, append-only audit trails

### C. Upsert

Updates existing rows based on upsert keys; inserts new rows if no match is found.

**Example** (upsert keys: `column_1`, `column_2`):

| Before Ingestion | Ingested Data | After Ingestion |
|------------------|---------------|-----------------|
| toto / 1 / 123   | toto / 3 / 28932 | toto / 1 / 123 |
| tata / 2 / 9823  | tata / 2 / 1034  | toto / 3 / 28932 |
|                  |                  | tata / 2 / 1034 |

**Requirements**:
- Upsert keys must be specified
- Combination of upsert keys must guarantee row uniqueness in the ingested dataset

**Uniqueness Validation**: The SDK will reject ingestion if duplicate upsert key combinations are detected:

```
# This will FAIL (duplicate key: toto/1)
column_1 / column_2 / column_3
toto     / 1        / 123
toto     / 1        / 28932  ❌ Duplicate
tata     / 2        / 1034
```

**Use Case**: Slowly changing dimensions, incremental updates, CDC (Change Data Capture)

## IX. Apache Iceberg Integration

All tables in the data lake use [Apache Iceberg](https://iceberg.apache.org/) format for advanced capabilities:

### Key Features

1. **ACID Transactions**: Guarantees consistency during concurrent reads/writes
2. **Schema Evolution**: Add, drop, or rename columns without rewriting data
3. **Time Travel**: Query historical table snapshots
4. **Partition Evolution**: Change partitioning scheme without data migration
5. **Hidden Partitioning**: Partition transformations hidden from users
6. **Upserts and Deletes**: Efficient row-level operations

### Table Format

- **Format Version**: 2 (required for Athena compatibility)
- **Storage**: Parquet files in S3
- **Catalog**: AWS Glue Data Catalog
- **Encryption**: SSE-S3

### Querying with Athena

```sql
-- Current data
SELECT * FROM my_database.my_table;

-- Time travel to specific snapshot
SELECT * FROM my_database.my_table 
FOR SYSTEM_TIME AS OF TIMESTAMP '2024-01-15 10:00:00';

-- Time travel by snapshot ID
SELECT * FROM my_database.my_table 
FOR SYSTEM_VERSION AS OF 123456789;
```

See [Athena Iceberg documentation](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html) for more details.

### Automatic Maintenance

The SDK automatically performs table maintenance:

- **Trigger**: Every 10 table versions (or when `force_maintenance=True`)
- **VACUUM**: Removes orphaned data files
- **OPTIMIZE**: Compacts small files using BIN_PACK strategy

**Manual Maintenance**:
```python
wrapper.perform_table_maintenance("database.table", force_maintenance=True)
```

**Maintenance Queries** (executed via Athena):
```sql
VACUUM table_name;
OPTIMIZE table_name REWRITE DATA USING BIN_PACK;
```

## X. Limitations / Assumptions

1. **AWS Region**: Default is `eu-west-1`. Must be explicitly configured if using another region.

2. **CSV Headers**: CSV files MUST contain headers. The SDK uses schema-on-read and cannot infer column names.

3. **Supported File Formats**: CSV, Parquet, JSON (JSON Lines format for native Python mode).

4. **Partition Limit**: Native Python mode automatically splits dataframes with >100 unique partition combinations to avoid Athena's `ICEBERG_TOO_MANY_OPEN_PARTITIONS` error.

5. **Stage Naming**: 
   - `stage_name = "prod"` results in databases without prefix (e.g., `my_database`)
   - All other stages add a prefix (e.g., `dev_my_database`)

6. **Naming Conventions**: 
   - S3 bucket names use hyphens (e.g., `project-domain-stage-data`)
   - Glue resources use underscores (e.g., `project_domain_stage`)
   
7. **Upsert Key Uniqueness**: The SDK validates uniqueness of upsert keys in the ingested dataset. Ingestion will fail if duplicates are detected.

8. **Concurrency**: Iceberg commit conflicts are automatically retried (up to 3 times with 180s delay). Table properties include extended retry configurations.

9. **Datalfred Requirements**: 
   - Requires `strands-agents` extra dependencies
   - Requires AWS Bedrock inference profiles named `{project_name}_{domain_name}_{stage_name}_{model_size}`
   - Available model sizes must be configured in Bedrock

10. **GitLab CI/CD**: The repository is mirrored from GitLab to GitHub. GitLab is the source of truth for CI/CD pipelines.

11. **Backend Configuration**: Terraform backend (if applicable) must be configured at initialization time, not hard-coded.

12. **Local Execution**: Uses default AWS credentials configured on the machine. Verify active AWS account before operations.

13. **Step Functions Integration**: When `step_function_task_token` is provided, the wrapper will send success/failure notifications to AWS Step Functions.

14. **SQL Job Mode**: When `IS_SQL_JOB=true`, the SDK expects a `main.sql` file in the `task_code/` directory.

15. **Table Configuration**: Optional YAML configuration files can be placed in `task_code/tables_configuration/{database}.{table}.yaml` for metadata management.
