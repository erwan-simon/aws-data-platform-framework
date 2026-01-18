import time
import awswrangler as wr
from datalake_sdk.base_processing_wrapper \
    import BaseProcessingWrapper
from datalake_sdk.delete_table import delete_table


def execute_sql_query(job: BaseProcessingWrapper,
                      database_name: str,
                      table_name: str):
    # result does not matter, we just want to see if the table can be read
    assert len(wr.athena.read_sql_query(
        sql=f"SELECT * FROM {table_name}",
        database=job.long_database_prefix + database_name,
        workgroup=job.athena_workgroup_name,
        boto3_session=job.boto_session,
        ctas_approach=False
    )) > 0


def check_table_metadata(job: BaseProcessingWrapper,
                         database_name: str,
                         table_name: str):
    glue_client = job.boto_session.client("glue")
    table_config = glue_client.get_table(
        DatabaseName=job.long_database_prefix + database_name,
        Name=table_name)["Table"]
    assert table_config.get("Description", "No description found") == "This is a test table"
    assert table_config["StorageDescriptor"]["Columns"][0]["Name"] == "name" \
        and table_config["StorageDescriptor"]["Columns"][0]["Comment"] == \
        "This column contains the names"
    assert table_config["StorageDescriptor"]["Columns"][1]["Name"] == "address" \
        and table_config["StorageDescriptor"]["Columns"][1]["Comment"] == \
        "This column contains the addresses"


def main(job: BaseProcessingWrapper):
    """
    The datalake sdk is the real entrypoint of the job,
    which then calls this function
    """
    short_database_name = "datalake_test"
    long_database_name = (
        f"{job.stage_name}_" if job.stage_name != "prod" else ""
    ) + short_database_name
    check_table_metadata(job, short_database_name, "test_native")
    check_table_metadata(job, short_database_name, "test_spark")
    execute_sql_query(job, short_database_name, "test_native_sql_entrypoint")
    execute_sql_query(job, short_database_name, "test_spark_sql_entrypoint")
    job.logger.info(
        f"Fetching and deleting tables for database {long_database_name}")
    deleted_at_least_one_database = False
    for table_name in wr.catalog.tables(
            database=long_database_name)["Table"].tolist():
        job.logger.info(f"Deleted table '{long_database_name}.{table_name}'")
        delete_table(
            job.logger, job.boto_session, job.project_name,
            job.domain_name, job.stage_name,
            short_database_name=short_database_name,
            table_name=table_name)
        deleted_at_least_one_database = True
    assert deleted_at_least_one_database, \
        f"Did not delete any table for database '{long_database_name}'"
