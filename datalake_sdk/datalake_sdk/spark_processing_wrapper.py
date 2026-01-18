from json.decoder import JSONDecodeError
from dataclasses import dataclass
from typing import List
import json
import sys
import os
from pyspark.sql import SparkSession, DataFrame
import awswrangler as wr
import boto3
from datalake_sdk.base_processing_wrapper import BaseProcessingWrapper


@dataclass
class SparkProcessingWrapper(BaseProcessingWrapper):
    spark_session: SparkSession = None
    aws_region_name: str = "eu-west-1"

    def __post_init__(self):
        super().__post_init__()
        technical_bucket_name = f"{self.project_name}-{self.domain_name}-" \
            f"{self.stage_name}-technical".replace("_", "-")
        self.spark_session = SparkSession \
            .builder \
            .config("hive.metastore.client.factory.class",
                    "com.amazonaws.glue.catalog.metastore."
                    "AWSGlueDataCatalogHiveClientFactory") \
            .config("spark.jars",
                    "/usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar") \
            .config("spark.sql.extensions",
                    "org.apache.iceberg.spark.extensions."
                    "IcebergSparkSessionExtensions") \
            .config("spark.sql.catalog.glue_catalog",
                    "org.apache.iceberg.spark.SparkCatalog") \
            .config("spark.sql.catalog.glue_catalog.catalog-impl",
                    "org.apache.iceberg.aws.glue.GlueCatalog") \
            .config("spark.sql.sources.partitionOverwriteMode", "dynamic") \
            .config("spark.sql.iceberg.handle-timestamp-without-timezone",
                    "true") \
            .config("spark.sql.catalog.glue_catalog.io-impl",
                    "org.apache.iceberg.aws.s3.S3FileIO") \
            .config("spark.sql.catalog.glue_catalog.cache-enabled",
                    "false") \
            .config("spark.sql.catalog.glue_catalog.warehouse",
                    f"s3://{technical_bucket_name}/data_catalog/") \
            .enableHiveSupport() \
            .getOrCreate()
        self.boto_session = boto3.session.Session(
            region_name=self.aws_region_name)

    def ingest(self, full_table_name: str, dataframe: DataFrame,
               override_ingestion_mode: str = None,
               force_maintenance: bool = False):
        if override_ingestion_mode:
            ingestion_mode = override_ingestion_mode
        else:
            ingestion_mode = self.output_tables[
                full_table_name]["ingestion_mode"]
        # long database name is used in glue data catalog (and thus athena)
        # short database name is used in s3 path
        long_database_name, table_name = \
            self.get_long_database_and_table_name(full_table_name)
        short_database_name = long_database_name.replace(
            self.long_database_prefix, "")
        if self.output_tables[full_table_name]["partition_keys"]:
            partition_keys_query_string = \
                ', '.join(self.output_tables[
                    full_table_name]["partition_keys"])
        else:
            partition_keys_query_string = ""
        dataframe.createOrReplaceTempView("dataset_to_ingest")
        if self.does_table_exist(full_table_name):
            self.ingest_data(
                long_database_name, short_database_name,
                table_name,
                ingestion_mode,
                self.output_tables[full_table_name]["upsert_keys"],
                partition_keys_query_string)
            self.perform_table_maintenance(full_table_name, force_maintenance)
        else:
            self.create_table_and_ingest_data(
                long_database_name, short_database_name, table_name,
                partition_keys_query_string)


    def read_input_dataset(self, input_file_path: str,
                           csv_delimiter: str = ",") -> DataFrame:
        file_type = self.get_input_dataset_file_type(input_file_path)
        if input_file_path.startswith("s3://"):
            input_file_path = input_file_path.replace("s3://", "s3a://")
        try:
            if file_type == "csv":
                return self.spark_session.read.option("header", "true") \
                    .options(delimiter=csv_delimiter).csv(input_file_path)
            if file_type == "parquet":
                return self.spark_session.read.parquet(input_file_path)
            raise ValueError(f"Unknwon file type '{file_type}'")
        except Exception as error:
            raise self.IngestionFailed(
                "Failed reading the input dataset at " +
                f"{input_file_path}") from error

    def create_table_and_ingest_data(
            self, long_database_name: str, short_database_name: str,
            table_name: str, partition_keys_query_string: str):
        data_bucket_name = str(
            f"{self.project_name}-{self.domain_name}-"
            f"{self.stage_name}-data").replace("_", "-")
        output_location = f"s3://{data_bucket_name}/" + \
            f"{short_database_name}/{table_name}"
        partitioned_by_partition_keys_query_string = "" \
            if not partition_keys_query_string else \
            f"PARTITIONED BY ({partition_keys_query_string})"
        cluster_by_partition_keys_query_string = "" \
            if not partition_keys_query_string else \
            f" CLUSTER BY ({partition_keys_query_string})"
        sql_query = f"""
            CREATE TABLE IF NOT EXISTS
            glue_catalog.{long_database_name}.{table_name}
            USING iceberg
            {partitioned_by_partition_keys_query_string}
            LOCATION '{output_location}'
            OPTIONS ('format-version'='2')
            TBLPROPERTIES (
                'table_type' = 'ICEBERG',
                'commit.retry.num-retries' = 30,
                'commit.retry.min-wait-ms' = 60000,
                'commit.retry.max-wait-ms' = 600000)
            AS SELECT * FROM dataset_to_ingest
            {cluster_by_partition_keys_query_string}
            """
        # format version 2 to make the table version compatible with Athena
        self.logger.info("Executing sql request" + sql_query)
        self.spark_session.sql(sql_query)

    def ingest_data(self, long_database_name: str, short_database_name: str,
                    table_name: str, ingestion_mode: str,
                    upsert_keys: List[str], partition_keys_query_string: str):
        cluster_by_partition_keys_query_string = "" \
            if not partition_keys_query_string else \
            f" CLUSTER BY ({partition_keys_query_string})"
        if ingestion_mode == "append":
            sql_query = (
                f"INSERT INTO glue_catalog.{long_database_name}."
                f"{table_name} SELECT * FROM dataset_to_ingest " +
                cluster_by_partition_keys_query_string)
        elif ingestion_mode == "overwrite":
            sql_query = (
                "INSERT OVERWRITE " +
                f"glue_catalog.{long_database_name}.{table_name} "
                "SELECT * FROM dataset_to_ingest " +
                cluster_by_partition_keys_query_string)
        elif ingestion_mode == "upsert":
            if not upsert_keys:
                raise ValueError(
                    "Did not find any upsert_keys for ingestion mode upsert "
                    f"for table {short_database_name}.{table_name}")
            merge_condition_expression_string = []
            for upsert_key in upsert_keys:
                if upsert_key not in self.spark_session.sql(
                        "SELECT * FROM dataset_to_ingest").columns:
                    raise ValueError(f"'{upsert_key}' upsert key " +
                                     "not found in input dataframe columns")
                merge_condition_expression_string.append(
                    f"old.{upsert_key} = new.{upsert_key}")
            if self.spark_session.sql(
                    "SELECT count FROM (SELECT " +
                    f"({', '.join(upsert_keys)}), count(*) AS count" +
                    " FROM dataset_to_ingest GROUP BY " +
                    f"({', '.join(upsert_keys)})) WHERE count > 1"
                    ).count() > 0:
                raise Exception(
                    "Upsert keys does not warantee unicity in the " +
                    "dataset you are trying to ingest. Failing because " +
                    "otherwise all those dupplicate rows would be added" +
                    " in the datalake and this is probably not what " +
                    "you want")
            sql_query = (
                f"MERGE INTO glue_catalog.{long_database_name}."
                f"{table_name} old USING (SELECT * FROM dataset_to_" +
                f"ingest {cluster_by_partition_keys_query_string})" +
                " new ON " +
                f"({' AND '.join(merge_condition_expression_string)})" +
                " WHEN MATCHED THEN UPDATE SET *"
                " WHEN NOT MATCHED THEN INSERT *")
        else:
            raise ValueError(
                f"Unknown ingestion mode named '{ingestion_mode}'.")
        self.logger.info("Executing sql request" + sql_query)
        self.spark_session.sql(sql_query)


def sql_entrypoint_processing_function(job: SparkProcessingWrapper):
    if len(list(job.output_tables.keys())) > 1:
        raise ValueError("Cannot use SQL entrypoint if there is more "
                         "than 1 table to write")
    with open("task_code/main.sql") as sql_request_file:
        sql_request_string = sql_request_file.read().format(
            database_prefix=f"glue_catalog.{job.long_database_prefix}")
    return {
        list(job.output_tables.keys())[0]: job.ProcessingResponse(
            dataframe=job.spark_session.sql(sql_request_string)
        )
    }


def job_entrypoint_function(execute=True) -> (
        SparkProcessingWrapper, object):
    try:
        formatted_argv = json.loads(sys.argv[1])
    except JSONDecodeError:
        # local execution
        formatted_argv = {}
    argv_without_task_additional_parameters = {}
    for argv_key, argv_value in formatted_argv.items():
        print(argv_key, argv_value)
        if argv_key.startswith("TASK_ADDITIONAL_PARAMETERS_"):
            os.environ[argv_key] = argv_value
        else:
            argv_without_task_additional_parameters[argv_key] = argv_value
    spark_processing_wrapper = SparkProcessingWrapper(
        **argv_without_task_additional_parameters
    )
    if spark_processing_wrapper.is_sql_job:
        processing_function = sql_entrypoint_processing_function
    else:
        from main import main as processing_function
    if execute:
        spark_processing_wrapper.execute(processing_function)
        return None
    return spark_processing_wrapper, processing_function


if __name__ == "__main__":
    job_entrypoint_function()
