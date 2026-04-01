import time
import os
import json
from datetime import datetime
from enum import Enum
from dataclasses import dataclass, field
from typing import Dict, Type, List, Union, NamedTuple, Callable
import logging
import boto3
import yaml
import awswrangler as wr
from datalake_sdk.tqdm_logging_handler import TqdmLoggingHandler


@dataclass
class BaseProcessingWrapper:
    project_name: str = os.environ["PROJECT_NAME"]
    domain_name: str = os.environ["DOMAIN_NAME"]
    stage_name: str = os.environ["STAGE_NAME"]
    pipeline_name: str = os.environ["PIPELINE_NAME"]
    task_name: str = os.environ["TASK_NAME"]
    is_sql_job: bool = os.environ["IS_SQL_JOB"].lower() == "true"
    boto_session: boto3.Session = boto3.session.Session(
        region_name="eu-west-1")
    input_tables: List[str] = field(
        default_factory=lambda: json.loads(os.getenv("INPUT_TABLES", "[]")))
    output_tables: Dict[str, Dict] = field(
        default_factory=lambda: json.loads(os.getenv("OUTPUT_TABLES", "{}")))
    step_function_task_token: Union[str, None] = None
    step_function_execution_arn: Union[str, None] = None
    logger: logging.Logger = logging.getLogger()
    logical_date: str = datetime.today().strftime('%Y-%m-%d')

    def __post_init__(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s [%(levelname)s] %(message)s',
            force=True)
        self.logger.setLevel(logging.INFO)
        # https://stackoverflow.com/a/38739634
        self.logger.addHandler(TqdmLoggingHandler())
        self.long_database_prefix = f"{self.stage_name}_" \
            if self.stage_name != "prod" else ""
        self.athena_workgroup_name = \
            f"{self.project_name}_{self.domain_name}_{self.stage_name}"
        if self.step_function_execution_arn:
            self.logical_date = self.boto_session.client(
                "stepfunctions").describe_execution(
                    executionArn=self.step_function_execution_arn
                )["startDate"].strftime('%Y-%m-%d')
        self.task_code_path = "/usr/app/src/task_code/"
        if self.output_tables and os.path.isdir(
                self.task_code_path + "tables_configuration"):
            for table_name in self.output_tables.keys():
                table_configuration_path = f"{self.task_code_path}/tables_configuration/" + \
                    f"{table_name}.yaml"
                if os.path.exists(table_configuration_path):
                    with open(table_configuration_path,
                              encoding="utf-8") as table_configuration_file:
                        table_configuration_dict = yaml.safe_load(table_configuration_file)
                    self.output_tables[table_name]["table_configuration"] = table_configuration_dict
        self.task_additional_parameters: Dict[str, str] = {
            key.replace("TASK_ADDITIONAL_PARAMETERS_", ""): value
            for key, value in os.environ.items()
            if key.startswith("TASK_ADDITIONAL_PARAMETERS_")
        }

        print("Logical date: " + str(self.logical_date))
        print("Is sql job: " + str(self.is_sql_job))
        print("Input tables: " + str(self.input_tables))
        print("Output tables: " + json.dumps(self.output_tables, indent=4))
        print("Task additional parameters: " +
              json.dumps(self.task_additional_parameters, indent=4))

    class IngestionFailed(Exception):
        pass

    class ProcessingFailed(Exception):
        pass

    def get_long_database_and_table_name(
            self, full_table_name: str) -> (str, str):
        long_database_name = \
            f"{self.long_database_prefix}{full_table_name.split('.')[0]}"
        table_name = full_table_name.split(".")[1]
        return long_database_name, table_name

    def does_table_exist(self, full_table_name: str) -> bool:
        long_database_name, table_name = self.get_long_database_and_table_name(
            full_table_name)
        glue_client = self.boto_session.client("glue")
        try:
            glue_client.get_table(DatabaseName=long_database_name,
                                  Name=table_name)
            self.logger.info(
                f"Found table {long_database_name}.{table_name}")
            return True
        except glue_client.exceptions.EntityNotFoundException:
            self.logger.info(
                "Did not find table " +
                f"{long_database_name}.{table_name}")
            return False

    def processing_function(self) -> Union[
            Type["pyspark.sql.DataFrame"],  # noqa: F821
            Type["pandas.DataFrame"]]:  # noqa: F821
        raise NotImplementedError(
            "This function has to be overriden by processing task.")

    class ProcessingResponse(NamedTuple):
        dataframe: Union[Type["pyspark.sql.DataFrame"],  # noqa: F821
                         Type["pandas.DataFrame"]] = None  # noqa: F821
        JobEndStatus: Enum = Enum("JobEndStatus", ["SUCCESS", "FAILURE"])
        job_end_status: Type["BaseProcessingWrapper.JobEndStatus"] = \
            JobEndStatus.SUCCESS
        job_end_message: str = "No end message given"
        override_ingestion_mode: str = None
        force_maintenance: bool = False

    def execute(self, processing_function: Callable[
            [], dict["BaseProcessingWrapper.ProcessingResponse"]] = None):
        sfn_client = self.boto_session.client("stepfunctions")
        try:
            self.logger.info(
                "Finished wrapper init. Launching processing function")
            try:
                if processing_function:
                    processing_response_list: Dict[
                        str, Type[
                            "BaseProcessingWrapper.ProcessingResponse"]
                    ] = processing_function(self)
                else:
                    processing_response_list: Dict[
                        str, Type[
                            "BaseProcessingWrapper.ProcessingResponse"]
                    ] = self.processing_function()
            except Exception as error:
                raise self.ProcessingFailed(str(error))
            failed_tables_list = []
            if processing_response_list:
                for full_table_name, processing_response in \
                        processing_response_list.items():
                    if not isinstance(processing_response,
                                      self.ProcessingResponse):
                        raise ValueError(
                            "Return value of processing function is not of "
                            "type ProcessingResponse. It is of type " +
                            str(type(processing_response)))
                    if processing_response.dataframe is not None:
                        self.logger.info(
                            f"Starting {full_table_name} ingestion")
                        self.ingest(full_table_name,
                                    processing_response.dataframe,
                                    processing_response.override_ingestion_mode,
                                    processing_response.force_maintenance)
                        self.logger.info(f"{full_table_name} ingestion success: "
                                         + processing_response.job_end_message)
                    else:
                        self.logger.info(
                            "No dataframe to ingest for table " +
                            full_table_name)
                    self.update_table_metadata(full_table_name)
                    if processing_response.job_end_status == "FAILURE":
                        failed_tables_list.append(full_table_name)
                        self.logger.error(
                            f"Processing job for table '{full_table_name}' "
                            "ended in FAILURE: " +
                            processing_response.job_end_message)
            if failed_tables_list:
                raise self.IngestionFailed(
                    "Following tables generation ended in failure state: " +
                    str(failed_tables_list))
            if self.step_function_task_token:
                if processing_response_list:
                    output = {
                        full_table_name: processing_response.job_end_message
                        for full_table_name, processing_response in
                        processing_response_list.items()}
                else:
                    output = {"result": "SUCCESS"}
                sfn_client.send_task_success(
                    taskToken=self.step_function_task_token,
                    output=json.dumps(output))
        except sfn_client.exceptions.TaskTimedOut as error:
            self.logger.error(str(error))
        except Exception as error:
            if self.step_function_task_token:
                sfn_client.send_task_failure(
                    taskToken=self.step_function_task_token,
                    error=str(type(error).__name__),
                    cause=str(error))
            raise error

    def get_input_dataset_file_type(self, input_file_path: str):
        if not input_file_path.startswith("s3://"):
            return input_file_path.split(".")[-1]
        s3_client = self.boto_session.client("s3")
        bucket_name = input_file_path.replace("s3://", "").split("/")[0]
        objects_prefix = input_file_path.replace(f"s3://{bucket_name}/", "")
        paginator = s3_client.get_paginator('list_objects_v2')
        file_type = None
        file_count = 0
        for response in paginator.paginate(Bucket=bucket_name,
                                           Prefix=objects_prefix):
            for content in response.get("Contents", []):
                current_file_type = content["Key"].split(".")[-1]
                if current_file_type in [
                        "csv", "parquet"]:
                    if not file_type:
                        file_type = current_file_type
                    elif file_type != current_file_type:
                        raise ValueError(
                            "Found conflicting file types in prefix s3://"
                            f"{bucket_name}/{objects_prefix}: {file_type}" +
                            f" and {current_file_type}")
                    file_count += 1
        if not file_type or file_count == 0:
            raise ValueError("Found no files to ingest with correct file " +
                             f"types: {bucket_name}/{objects_prefix}")
        self.logger.info(f"Found {file_count} files with type {file_type}")
        return file_type

    def update_table_metadata(self, full_table_name):
        self.logger.info(f"Updating metadata for table {full_table_name}")
        long_database_name, table_name = \
            self.get_long_database_and_table_name(full_table_name)
        glue_client = self.boto_session.client("glue")
        if not wr.catalog.does_table_exist(database=long_database_name, table=table_name):
            self.logger.warning(f"Table {full_table_name} does not exist, not updating metadata")
            return
        table_current_config = glue_client.get_table(
            DatabaseName=long_database_name, Name=table_name)["Table"]
        for key_to_remove in [
                "DatabaseName", "IsMultiDialectView",
                "CreateTime", "UpdateTime",
                "LastAccessTime", "LastAccessTime",
                "LastAnalyzedTime", "CreatedBy",
                "IsRegisteredWithLakeFormation",
                "CatalogId", "VersionId", "IsMaterializedView"]:
            table_current_config.pop(key_to_remove, None)
        if self.output_tables[full_table_name].get(
                "table_configuration", {}).get("description"):
            table_current_config["Description"] = self.output_tables[
                full_table_name]["table_configuration"]["description"]
        if self.output_tables[full_table_name].get(
                "table_configuration", {}).get("schema"):
            for column_name, column_dict in self.output_tables[
                    full_table_name]["table_configuration"]["schema"].items():
                for column_dict_iter in table_current_config.get(
                        "PartitionKeys", []) + table_current_config[
                            "StorageDescriptor"].get("Columns", []):
                    if column_dict_iter["Name"] == column_name:
                        column_dict_iter["Comment"] = column_dict["description"]
        glue_client.update_table(
            DatabaseName=long_database_name,
            TableInput=table_current_config)
        self.logger.info(f"Updated metadata for table {full_table_name}")

    def perform_table_maintenance(self, full_table_name: str, force_maintenance: bool = False) -> bool:
        """
        https://iceberg.apache.org/docs/latest/maintenance/
        """
        long_database_name, table_name = \
            self.get_long_database_and_table_name(full_table_name)
        table_version_id = int(
            self.boto_session.client("glue").get_table(
                DatabaseName=long_database_name, Name=table_name)["Table"]["VersionId"]
        )
        if not force_maintenance and table_version_id != 0 and table_version_id % 10 != 0:
            self.logger.info(
                f"Not performing maintenance for table {full_table_name} as "
                f"table version ID '{table_version_id}' did not trigger it.")
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
        vacuum_reason = vacuum_resp["Status"].get("StateChangeReason", "No message found")

        if vacuum_state != "SUCCEEDED":
            raise RuntimeError(f"VACUUM failed: {vacuum_reason}")

        # --- OPTIMIZE (boucle si MORE_RUNS_NEEDED) ---
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
        self.logger.info(f"Performed maintenance for table {full_table_name}")
        return True
