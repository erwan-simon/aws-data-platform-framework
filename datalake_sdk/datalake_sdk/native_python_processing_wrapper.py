import json
import os
import time
from dataclasses import dataclass
import uuid
import pandas as pd
import awswrangler as wr
from datalake_sdk.base_processing_wrapper import (
    BaseProcessingWrapper,
    parse_debug_flag,
)


@dataclass
class NativePythonProcessingWrapper(BaseProcessingWrapper):
    def __post_init__(self):
        super().__post_init__()
        self.SLEEP_TIME_BETWEEN_INGESTION_RETRIES = 180
        self.MAX_INGESTION_RETRIES = 3

    def _create_partitioned_dataframes(
        self,
        df: pd.DataFrame,
        partition_cols: list[str] | None,
    ) -> list[pd.DataFrame]:
        """
        Split the DataFrame into multiple DataFrames each containing at
        most chunk_size unique combinations of partition columns.
        """
        if not partition_cols or len(df) == 0:
            return [df]

        # Get all unique combinations of the partition columns
        unique_combinations = df[partition_cols].drop_duplicates()
        # Split the unique combinations into chunks of chunk_size

        def chunkify(list_to_chunkify, chunk_size):
            """
            Yield successive chunk_size-sized chunks from list_to_chunkify.
            """
            for i in range(0, len(list_to_chunkify), chunk_size):
                yield list_to_chunkify[i : i + chunk_size]

        if len(unique_combinations.values.tolist()) < 100:
            return [df]
        partitioned_dfs = []
        for chunk in chunkify(unique_combinations.values.tolist(), 100):
            chunk_df = pd.DataFrame(chunk, columns=partition_cols).astype(
                dtype={
                    partition_col_name: df.dtypes[partition_col_name]
                    for partition_col_name in partition_cols
                }
            )
            # Merge the original DataFrame with the chunk to get the corresponding rows
            partitioned_df = df.merge(chunk_df, on=partition_cols)
            partitioned_dfs.append(partitioned_df)
        self.logger.info(
            f"Created {len(partitioned_dfs)} dataframe chunk to avoid "
            "ICEBERG_TOO_MANY_OPEN_PARTITIONS Athena error"
        )
        return partitioned_dfs

    def read_input_dataset(
        self, input_file_path: str, csv_delimiter: str = ","
    ) -> pd.DataFrame:
        file_type = self.get_input_dataset_file_type(input_file_path)
        try:
            if file_type == "csv":
                if input_file_path.startswith("s3://"):
                    return wr.s3.read_csv(input_file_path, delimiter=csv_delimiter)
                return pd.read_csv(input_file_path, delimiter=csv_delimiter)
            if file_type == "parquet":
                if input_file_path.startswith("s3://"):
                    return wr.s3.read_parquet(input_file_path)
                return pd.read_parquet(input_file_path)
            if file_type == "json":
                if input_file_path.startswith("s3://"):
                    return wr.s3.read_json(input_file_path, lines=True)
                return pd.read_json(input_file_path, lines=True)
            raise ValueError(f"Unknwon file type '{file_type}'")
        except Exception as error:
            raise self.IngestionFailed(
                "Failed reading the input dataset at " + f"{input_file_path}"
            ) from error

    def ingest(
        self,
        full_table_name: str,
        dataframe: pd.DataFrame,
        recursive_counter: int = 1,
        override_ingestion_mode: str = None,
        force_maintenance: bool = False,
    ):
        self._validate_output_schema(full_table_name, dataframe)
        final_ingestion_mode = (
            override_ingestion_mode
            if override_ingestion_mode
            else self.output_tables[full_table_name]["ingestion_mode"]
        )
        # long database name is used in glue data catalog (and thus athena)
        # short database name is used in s3 path
        long_database_name, table_name = self.get_long_database_and_table_name(
            full_table_name
        )
        short_database_name = long_database_name.replace(self.long_database_prefix, "")
        data_bucket_name = str(
            f"{self.project_name}-{self.domain_name}-{self.stage_name}-data"
        ).replace("_", "-")
        technical_bucket_uri = self.boto_session.client("athena").get_work_group(
            WorkGroup=self.athena_workgroup_name
        )["WorkGroup"]["Configuration"]["ResultConfiguration"]["OutputLocation"]
        output_location = (
            f"s3://{data_bucket_name}/" + f"{short_database_name}/{table_name}"
        )
        # https://github.com/aws/aws-sdk-pandas/issues/2502
        ingestion_temp_path = (
            technical_bucket_uri
            + f"{short_database_name}"
            + f"/{table_name}/{str(uuid.uuid4())}"
        )
        try:
            partitioned_dfs = self._create_partitioned_dataframes(
                dataframe.copy(),
                self.output_tables[full_table_name].get("partition_keys", []),
            )
            for index, df_chunk in enumerate(partitioned_dfs):
                wr.athena.to_iceberg(
                    df=df_chunk,
                    database=long_database_name,
                    table=table_name,
                    table_location=output_location,
                    partition_cols=self.output_tables[full_table_name].get(
                        "partition_keys", []
                    ),
                    merge_cols=[]
                    if self.output_tables[full_table_name]["ingestion_mode"] != "upsert"
                    else self.output_tables[full_table_name]["upsert_keys"],
                    workgroup=self.athena_workgroup_name,
                    encryption="SSE_S3",
                    mode=final_ingestion_mode,
                    boto3_session=self.boto_session,
                    temp_path=ingestion_temp_path + f"/{index}",
                )
                self.perform_table_maintenance(full_table_name, force_maintenance)
        except wr.exceptions.EmptyDataFrame:
            self.logger.warning("Ingested empty dataframe")
        except wr.exceptions.QueryFailed as error:
            if "ICEBERG_COMMIT_ERROR" not in str(error):
                raise error
            # https://repost.aws/questions/QU8YsvJ_V4TIyVZhbwhk0mww/athena-throttlingexception-errors
            self.logger.warning(
                "Athena encountered a concurrency issue with Iceberg, retrying..."
            )
            time.sleep(self.SLEEP_TIME_BETWEEN_INGESTION_RETRIES)
            if recursive_counter > self.MAX_INGESTION_RETRIES:
                raise ValueError(
                    f"Exceeded retry limit ({recursive_counter}) for "
                    "ingestion: " + str(error)
                ) from error
            self.ingest(full_table_name, dataframe, recursive_counter + 1)
        self.record_upsert_keys(full_table_name)
        self.record_producer_job(full_table_name)
        if not wr.catalog.does_table_exist(
            database=long_database_name, table=table_name
        ):
            return
        wr.catalog.upsert_table_parameters(
            database=long_database_name,
            table=table_name,
            boto3_session=self.boto_session,
            parameters={
                "commit.retry.num-retries": "30",
                "commit.retry.max-wait-ms": "600000",
                "commit.retry.min-wait-ms": "120000",
            },
        )


def sql_entrypoint_processing_function(self):
    if len(list(self.output_tables.keys())) > 1:
        raise ValueError(
            "Cannot use SQL entrypoint if there is more than 1 table to write"
        )
    with open("task_code/main.sql") as sql_request_file:
        sql_request_string = sql_request_file.read().format(
            database_prefix=self.long_database_prefix,
            logical_date=self.logical_date,
        )
    return {
        list(self.output_tables.keys())[0]: self.ProcessingResponse(
            dataframe=wr.athena.read_sql_query(
                sql=sql_request_string,
                database=list(self.output_tables.keys())[0].split(".")[0],
                workgroup=self.athena_workgroup_name,
                boto3_session=self.boto_session,
                ctas_approach=False,
            ),
        )
    }


def job_entrypoint_function(execute=True) -> (NativePythonProcessingWrapper, object):
    execution_input = json.loads(os.getenv("step_function_execution_input") or "{}")
    native_processing_wrapper = NativePythonProcessingWrapper(
        step_function_task_token=os.getenv("step_function_task_token"),
        step_function_execution_arn=os.getenv("step_function_execution_arn"),
        logical_date=execution_input.get("logical_date") or "",
        debug=parse_debug_flag(execution_input.get("debug")),
    )
    if native_processing_wrapper.is_sql_job:
        processing_function = sql_entrypoint_processing_function
    else:
        from main import main as processing_function
    if execute:
        native_processing_wrapper.execute(processing_function)
        return None
    return native_processing_wrapper, processing_function


if __name__ == "__main__":
    job_entrypoint_function()
