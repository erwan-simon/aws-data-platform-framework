import time
import os
import json
from datetime import datetime
from enum import Enum
from dataclasses import dataclass, field
from typing import Any, Dict, Type, List, Union, NamedTuple, Callable
import logging
import boto3
import yaml
import awswrangler as wr
import pandera.pandas as pa
from datalake_sdk.schema_loader import build_pandera_schema
from datalake_sdk.tqdm_logging_handler import TqdmLoggingHandler


def parse_debug_flag(value: Any) -> bool:
    """Parse the ``debug`` flag coming from the Step Functions execution input.

    Accepts JSON booleans and the string forms users routinely type by mistake
    in the SFN console (``"true"``, ``"false"``, ``"1"``, ``"0"``). Raises on
    anything else so the task fails fast at startup rather than silently
    enabling or disabling DEBUG — Python's default ``bool("false") is True``
    is exactly the footgun we want to avoid.
    """
    if value is None or value is False:
        return False
    if value is True:
        return True
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in ("true", "1"):
            return True
        if normalized in ("false", "0", ""):
            return False
    raise ValueError(
        f"Invalid value for 'debug' in step function execution input: "
        f"{value!r}. Expected JSON boolean (true/false) or string "
        "('true'/'false'/'1'/'0')."
    )


@dataclass
class BaseProcessingWrapper:
    project_name: str = os.environ["PROJECT_NAME"]
    domain_name: str = os.environ["DOMAIN_NAME"]
    stage_name: str = os.environ["STAGE_NAME"]
    pipeline_name: str = os.environ["PIPELINE_NAME"]
    task_name: str = os.environ["TASK_NAME"]
    is_sql_job: bool = os.environ["IS_SQL_JOB"].lower() == "true"
    boto_session: boto3.Session = boto3.session.Session(region_name="eu-west-1")
    input_tables: List[str] = field(
        default_factory=lambda: json.loads(os.getenv("INPUT_TABLES", "[]"))
    )
    output_tables: Dict[str, Dict] = field(
        default_factory=lambda: json.loads(os.getenv("OUTPUT_TABLES", "{}"))
    )
    step_function_task_token: Union[str, None] = None
    step_function_execution_arn: Union[str, None] = None
    logger: logging.Logger = logging.getLogger()
    logical_date: str = ""
    debug: bool = False

    def __post_init__(self):
        log_level = logging.DEBUG if self.debug else logging.INFO
        logging.basicConfig(
            level=log_level,
            format="%(asctime)s [%(levelname)s] %(message)s",
            force=True,
        )
        self.logger.setLevel(log_level)
        # https://stackoverflow.com/a/38739634
        self.logger.addHandler(TqdmLoggingHandler())
        self.long_database_prefix = (
            f"{self.stage_name}_" if self.stage_name != "prod" else ""
        )
        self.athena_workgroup_name = (
            f"{self.project_name}_{self.domain_name}_{self.stage_name}"
        )
        if self.logical_date:
            # Explicit override from Step Function execution input — fail-fast
            # on bad format and canonicalise to zero-padded YYYY-MM-DD so
            # downstream partition keys stay consistent with the startDate path.
            self.logical_date = datetime.strptime(
                self.logical_date, "%Y-%m-%d"
            ).strftime("%Y-%m-%d")
        elif self.step_function_execution_arn:
            self.logical_date = (
                self.boto_session.client("stepfunctions")
                .describe_execution(executionArn=self.step_function_execution_arn)[
                    "startDate"
                ]
                .strftime("%Y-%m-%d")
            )
        else:
            self.logical_date = datetime.today().strftime("%Y-%m-%d")
        self.task_code_path = "/usr/app/src/task_code/"
        self.pandera_schemas: Dict[str, pa.DataFrameSchema] = {}
        if self.output_tables and os.path.isdir(
            self.task_code_path + "tables_configuration"
        ):
            for table_name in self.output_tables.keys():
                table_configuration_path = (
                    f"{self.task_code_path}/tables_configuration/"
                    + f"{table_name}.yaml"
                )
                if os.path.exists(table_configuration_path):
                    with open(
                        table_configuration_path, encoding="utf-8"
                    ) as table_configuration_file:
                        table_configuration_dict = yaml.safe_load(
                            table_configuration_file
                        )
                    self.output_tables[table_name]["table_configuration"] = (
                        table_configuration_dict
                    )
                    built_schema = build_pandera_schema(table_configuration_dict)
                    if built_schema is not None:
                        self.pandera_schemas[table_name] = built_schema
        self.task_additional_parameters: Dict[str, str] = {
            key.replace("TASK_ADDITIONAL_PARAMETERS_", ""): value
            for key, value in os.environ.items()
            if key.startswith("TASK_ADDITIONAL_PARAMETERS_")
        }

        print("Logical date: " + str(self.logical_date))
        print("Debug logging: " + str(self.debug))
        print("Is sql job: " + str(self.is_sql_job))
        print("Input tables: " + str(self.input_tables))
        print("Output tables: " + json.dumps(self.output_tables, indent=4))
        print(
            "Task additional parameters: "
            + json.dumps(self.task_additional_parameters, indent=4)
        )

    class IngestionFailed(Exception):
        pass

    def _validate_output_schema(self, full_table_name: str, dataframe: Any) -> None:
        """Run the pandera schema (if any) against the output dataframe.

        Collects every failure via `lazy=True`, logs `failure_cases`, and
        raises `IngestionFailed` chained on the original pandera error so
        callers can still introspect `exc.__cause__.failure_cases`.
        """
        schema = self.pandera_schemas.get(full_table_name)
        if schema is None:
            return
        try:
            schema.validate(dataframe, lazy=True)
        except pa.errors.SchemaErrors as err:
            self.logger.error(
                "Schema validation failed for %s\n%s",
                full_table_name,
                err.failure_cases.to_string(),
            )
            raise self.IngestionFailed(
                f"Schema validation failed for {full_table_name} "
                f"({len(err.failure_cases)} failure cases — see logs)"
            ) from err

    class ProcessingFailed(Exception):
        pass

    def get_long_database_and_table_name(self, full_table_name: str) -> (str, str):
        long_database_name = (
            f"{self.long_database_prefix}{full_table_name.split('.')[0]}"
        )
        table_name = full_table_name.split(".")[1]
        return long_database_name, table_name

    UPSERT_KEYS_TABLE_PROPERTY = "datalake_sdk_upsert_keys"
    PIPELINE_NAME_TABLE_PROPERTY = "datalake_sdk_pipeline_name"
    TASK_NAME_TABLE_PROPERTY = "datalake_sdk_task_name"

    def record_producer_job(self, full_table_name: str) -> None:
        """
        Record the pipeline/task that produced this table on the Glue
        table properties. No-op when running outside of a pipeline (e.g.
        ad-hoc CLI ingestion) or when the table does not exist yet.
        """
        if not self.pipeline_name or not self.task_name:
            return
        long_database_name, table_name = self.get_long_database_and_table_name(
            full_table_name
        )
        glue_client = self.boto_session.client("glue")
        try:
            table_dict = glue_client.get_table(
                DatabaseName=long_database_name, Name=table_name
            )["Table"]
        except glue_client.exceptions.EntityNotFoundException:
            return
        current_params = table_dict.get("Parameters", {})
        new_params = {}
        if current_params.get(self.PIPELINE_NAME_TABLE_PROPERTY) != self.pipeline_name:
            new_params[self.PIPELINE_NAME_TABLE_PROPERTY] = self.pipeline_name
        if current_params.get(self.TASK_NAME_TABLE_PROPERTY) != self.task_name:
            new_params[self.TASK_NAME_TABLE_PROPERTY] = self.task_name
        if not new_params:
            return
        wr.catalog.upsert_table_parameters(
            database=long_database_name,
            table=table_name,
            boto3_session=self.boto_session,
            parameters=new_params,
        )
        self.logger.info(
            f"Recorded producer job '{self.pipeline_name}/{self.task_name}' "
            f"on table {full_table_name}"
        )

    def record_upsert_keys(self, full_table_name: str) -> None:
        """
        For upsert ingestions: record the upsert keys used for this write
        on the Glue table properties. If a value already exists and differs,
        log a warning and overwrite it with the current keys.
        """
        if self.output_tables[full_table_name].get("ingestion_mode") != "upsert":
            return
        upsert_keys = self.output_tables[full_table_name].get("upsert_keys", [])
        if not upsert_keys:
            return
        long_database_name, table_name = self.get_long_database_and_table_name(
            full_table_name
        )
        glue_client = self.boto_session.client("glue")
        try:
            table_dict = glue_client.get_table(
                DatabaseName=long_database_name, Name=table_name
            )["Table"]
        except glue_client.exceptions.EntityNotFoundException:
            return
        stored = table_dict.get("Parameters", {}).get(self.UPSERT_KEYS_TABLE_PROPERTY)
        expected = ",".join(upsert_keys)
        if stored == expected:
            return
        if stored is not None and stored != expected:
            self.logger.warning(
                f"Upsert keys for table {full_table_name} changed: "
                f"'{stored}' -> '{expected}'. Updating table property "
                f"'{self.UPSERT_KEYS_TABLE_PROPERTY}'."
            )
        wr.catalog.upsert_table_parameters(
            database=long_database_name,
            table=table_name,
            boto3_session=self.boto_session,
            parameters={self.UPSERT_KEYS_TABLE_PROPERTY: expected},
        )
        self.logger.info(
            f"Recorded upsert_keys '{expected}' on table {full_table_name}"
        )

    def does_table_exist(self, full_table_name: str) -> bool:
        long_database_name, table_name = self.get_long_database_and_table_name(
            full_table_name
        )
        glue_client = self.boto_session.client("glue")
        try:
            glue_client.get_table(DatabaseName=long_database_name, Name=table_name)
            self.logger.info(f"Found table {long_database_name}.{table_name}")
            return True
        except glue_client.exceptions.EntityNotFoundException:
            self.logger.info(
                "Did not find table " + f"{long_database_name}.{table_name}"
            )
            return False

    def processing_function(
        self,
    ) -> Union[
        Type["pyspark.sql.DataFrame"],  # noqa: F821
        Type["pandas.DataFrame"],  # noqa: F821
    ]:
        raise NotImplementedError(
            "This function has to be overriden by processing task."
        )

    class ProcessingResponse(NamedTuple):
        dataframe: Union[
            Type["pyspark.sql.DataFrame"],  # noqa: F821
            Type["pandas.DataFrame"],  # noqa: F821
        ] = None
        JobEndStatus: Enum = Enum("JobEndStatus", ["SUCCESS", "FAILURE"])
        job_end_status: Type["BaseProcessingWrapper.JobEndStatus"] = (
            JobEndStatus.SUCCESS
        )
        job_end_message: str = "No end message given"
        override_ingestion_mode: str = None
        force_maintenance: bool = False

    def execute(
        self,
        processing_function: Callable[
            [], dict["BaseProcessingWrapper.ProcessingResponse"]
        ] = None,
    ):
        sfn_client = self.boto_session.client("stepfunctions")
        try:
            self.logger.info("Finished wrapper init. Launching processing function")
            try:
                if processing_function:
                    processing_response_list: Dict[
                        str, Type["BaseProcessingWrapper.ProcessingResponse"]
                    ] = processing_function(self)
                else:
                    processing_response_list: Dict[
                        str, Type["BaseProcessingWrapper.ProcessingResponse"]
                    ] = self.processing_function()
            except Exception as error:
                raise self.ProcessingFailed(str(error))
            failed_tables_list = []
            if processing_response_list:
                for (
                    full_table_name,
                    processing_response,
                ) in processing_response_list.items():
                    if not isinstance(processing_response, self.ProcessingResponse):
                        raise ValueError(
                            "Return value of processing function is not of "
                            "type ProcessingResponse. It is of type "
                            + str(type(processing_response))
                        )
                    if processing_response.dataframe is not None:
                        self.logger.info(f"Starting {full_table_name} ingestion")
                        self.ingest(
                            full_table_name,
                            processing_response.dataframe,
                            processing_response.override_ingestion_mode,
                            processing_response.force_maintenance,
                        )
                        self.logger.info(
                            f"{full_table_name} ingestion success: "
                            + processing_response.job_end_message
                        )
                    else:
                        self.logger.info(
                            "No dataframe to ingest for table " + full_table_name
                        )
                    self.update_table_metadata(full_table_name)
                    if processing_response.job_end_status == "FAILURE":
                        failed_tables_list.append(full_table_name)
                        self.logger.error(
                            f"Processing job for table '{full_table_name}' "
                            "ended in FAILURE: " + processing_response.job_end_message
                        )
            if failed_tables_list:
                raise self.IngestionFailed(
                    "Following tables generation ended in failure state: "
                    + str(failed_tables_list)
                )
            if self.step_function_task_token:
                if processing_response_list:
                    output = {
                        full_table_name: processing_response.job_end_message
                        for full_table_name, processing_response in processing_response_list.items()
                    }
                else:
                    output = {"result": "SUCCESS"}
                sfn_client.send_task_success(
                    taskToken=self.step_function_task_token, output=json.dumps(output)
                )
        except sfn_client.exceptions.TaskTimedOut as error:
            self.logger.error(str(error))
        except Exception as error:
            if self.step_function_task_token:
                sfn_client.send_task_failure(
                    taskToken=self.step_function_task_token,
                    error=str(type(error).__name__),
                    cause=str(error),
                )
            raise error

    def get_input_dataset_file_type(self, input_file_path: str):
        if not input_file_path.startswith("s3://"):
            return input_file_path.split(".")[-1]
        s3_client = self.boto_session.client("s3")
        bucket_name = input_file_path.replace("s3://", "").split("/")[0]
        objects_prefix = input_file_path.replace(f"s3://{bucket_name}/", "")
        paginator = s3_client.get_paginator("list_objects_v2")
        file_type = None
        file_count = 0
        for response in paginator.paginate(Bucket=bucket_name, Prefix=objects_prefix):
            for content in response.get("Contents", []):
                current_file_type = content["Key"].split(".")[-1]
                if current_file_type in ["csv", "parquet"]:
                    if not file_type:
                        file_type = current_file_type
                    elif file_type != current_file_type:
                        raise ValueError(
                            "Found conflicting file types in prefix s3://"
                            f"{bucket_name}/{objects_prefix}: {file_type}"
                            + f" and {current_file_type}"
                        )
                    file_count += 1
        if not file_type or file_count == 0:
            raise ValueError(
                "Found no files to ingest with correct file "
                + f"types: {bucket_name}/{objects_prefix}"
            )
        self.logger.info(f"Found {file_count} files with type {file_type}")
        return file_type

    def update_table_metadata(self, full_table_name):
        self.logger.info(f"Updating metadata for table {full_table_name}")
        long_database_name, table_name = self.get_long_database_and_table_name(
            full_table_name
        )
        glue_client = self.boto_session.client("glue")
        if not wr.catalog.does_table_exist(
            database=long_database_name, table=table_name
        ):
            self.logger.warning(
                f"Table {full_table_name} does not exist, not updating metadata"
            )
            return
        table_current_config = glue_client.get_table(
            DatabaseName=long_database_name, Name=table_name
        )["Table"]
        for key_to_remove in [
            "DatabaseName",
            "IsMultiDialectView",
            "CreateTime",
            "UpdateTime",
            "LastAccessTime",
            "LastAccessTime",
            "LastAnalyzedTime",
            "CreatedBy",
            "IsRegisteredWithLakeFormation",
            "CatalogId",
            "VersionId",
            "IsMaterializedView",
        ]:
            table_current_config.pop(key_to_remove, None)
        if (
            self.output_tables[full_table_name]
            .get("table_configuration", {})
            .get("description")
        ):
            table_current_config["Description"] = self.output_tables[full_table_name][
                "table_configuration"
            ]["description"]
        if (
            self.output_tables[full_table_name]
            .get("table_configuration", {})
            .get("schema")
        ):
            for column_name, column_dict in self.output_tables[full_table_name][
                "table_configuration"
            ]["schema"].items():
                for column_dict_iter in table_current_config.get(
                    "PartitionKeys", []
                ) + table_current_config["StorageDescriptor"].get("Columns", []):
                    if column_dict_iter["Name"] == column_name:
                        column_dict_iter["Comment"] = column_dict["description"]
        glue_client.update_table(
            DatabaseName=long_database_name, TableInput=table_current_config
        )
        self.logger.info(f"Updated metadata for table {full_table_name}")

    def perform_table_maintenance(
        self, full_table_name: str, force_maintenance: bool = False
    ) -> bool:
        """
        https://iceberg.apache.org/docs/latest/maintenance/
        """
        long_database_name, table_name = self.get_long_database_and_table_name(
            full_table_name
        )
        glue_client = self.boto_session.client("glue")
        table_before_maintenance = glue_client.get_table(
            DatabaseName=long_database_name, Name=table_name
        )["Table"]
        table_version_id = int(table_before_maintenance["VersionId"])
        parameters_before_maintenance = table_before_maintenance.get("Parameters", {})
        if (
            not force_maintenance
            and table_version_id != 0
            and table_version_id % 10 != 0
        ):
            self.logger.info(
                f"Not performing maintenance for table {full_table_name} as "
                f"table version ID '{table_version_id}' did not trigger it."
            )
            return False
        message = f"Performing maintenance for table {full_table_name}"
        if force_maintenance:
            message += " as force_maintenance was set to True"
        else:
            message += f" as table version ID '{table_version_id}' triggered it."
        self.logger.info(message)
        terminal_states = {"SUCCEEDED", "FAILED", "CANCELLED"}

        def wait_for_query(query_execution_id):
            while True:
                resp = wr.athena.get_query_execution(
                    query_execution_id,
                    boto3_session=self.boto_session,
                )
                state = resp["Status"]["State"]
                if state in terminal_states:
                    return resp
                self.logger.info("Sleeping waiting for query to finish...")
                time.sleep(5)

        # not using read_sql_query query as it adds double quotes around table names in the SQL query string and it is not compatible with the VACUUM command
        self.logger.info("Performing vacuum...")
        vacuum_query_id = wr.athena.start_query_execution(
            f"VACUUM {table_name}",
            database=long_database_name,
            workgroup=self.athena_workgroup_name,
            boto3_session=self.boto_session,
        )

        vacuum_resp = wait_for_query(vacuum_query_id)

        vacuum_state = vacuum_resp["Status"]["State"]
        vacuum_reason = vacuum_resp["Status"].get(
            "StateChangeReason", "No message found"
        )

        if vacuum_state != "SUCCEEDED":
            raise RuntimeError(f"VACUUM failed: {vacuum_reason}")

        # --- OPTIMIZE (loop if MORE_RUNS_NEEDED) ---
        self.logger.info("Performing optimize...")
        while True:
            optimize_query_id = wr.athena.start_query_execution(
                f"OPTIMIZE {table_name} REWRITE DATA USING BIN_PACK",
                database=long_database_name,
                workgroup=self.athena_workgroup_name,
                boto3_session=self.boto_session,
            )

            optimize_resp = wait_for_query(optimize_query_id)

            status = optimize_resp["Status"]
            state = status["State"]
            reason = status.get("StateChangeReason", "No error message found")

            if state == "SUCCEEDED":
                break

            if (
                state == "FAILED"
                and reason
                and "ICEBERG_OPTIMIZE_MORE_RUNS_NEEDED" in reason
            ):
                self.logger.info(
                    "OPTIMIZE failed with ICEBERG_OPTIMIZE_MORE_RUNS_NEEDED, retrying..."
                )
                continue

            raise RuntimeError(f"OPTIMIZE failed: {reason}")
        # VACUUM/OPTIMIZE rewrites the Glue table entry and drops custom Parameters
        if parameters_before_maintenance:
            wr.catalog.upsert_table_parameters(
                database=long_database_name,
                table=table_name,
                boto3_session=self.boto_session,
                parameters=parameters_before_maintenance,
            )
        self.logger.info(f"Performed maintenance for table {full_table_name}")
        return True
