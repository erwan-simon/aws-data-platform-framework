# Part of the platform's integration-test fixtures. Useful as a working multi-table example; safe to delete in a real domain.
from typing import Union
import random
import pandas as pd
import awswrangler as wr

try:
    IS_SPARK_ENVIRONMENT = True
    from pyspark.sql.types import (
        StructType,
        StructField,
        StringType,
        DateType,
        LongType,
    )
    from pyspark.sql import DataFrame
except ModuleNotFoundError:
    print("Not in a spark environment")
    IS_SPARK_ENVIRONMENT = False
from datalake_sdk.base_processing_wrapper import BaseProcessingWrapper

from mimesis import Person
from mimesis import Address
from mimesis.enums import Gender
from mimesis import Datetime

try:
    from pipeline_utils.main import main as pipeline_utils_main
except Exception:
    # https://pypi.org/project/pipeline-utils/
    raise Exception(
        "Failed to import pipeline_utils.main. Check that you are installing the pipeline_utils library from private repository and not the public one"
    )

person = Person()
addess = Address()
mimesis_datetime = Datetime()


def create_fake_data(number_of_rows_to_create: int = 1) -> list:
    return [
        {
            "name": person.full_name(gender=Gender.FEMALE),
            "address": addess.address(),
            "email": person.email(),
            "city": addess.city(),
            "state": addess.state(),
            "date_time": mimesis_datetime.datetime(),
            "randomdata": random.randint(1000, 2000),
        }
        for x in range(number_of_rows_to_create)
    ]


def convert_list_to_dataframe(
    job: BaseProcessingWrapper, data: list
) -> Union[pd.DataFrame, "DataFrame"]:
    if IS_SPARK_ENVIRONMENT:
        return job.spark_session.createDataFrame(
            data=data,
            schema=StructType(
                [
                    StructField("name", StringType(), True),
                    StructField("address", StringType(), True),
                    StructField("email", StringType(), True),
                    StructField("city", StringType(), True),
                    StructField("state", StringType(), True),
                    StructField("date_time", DateType(), True),
                    StructField("randomdata", LongType(), True),
                ]
            ),
        )
    return pd.DataFrame(data)


def test_upsert(job: BaseProcessingWrapper, database_name: str, table_prefix: str):
    full_table_name = f"{database_name}.{table_prefix}_upsert"
    fake_data = create_fake_data(100)
    fake_data[0]["name"] = "Michel"
    fake_data[0]["city"] = "Paris"
    job.ingest(
        full_table_name=full_table_name,
        dataframe=convert_list_to_dataframe(job, fake_data),
        override_ingestion_mode="overwrite",
    )
    fake_data_2 = create_fake_data(2)
    fake_data_2[0]["name"] = "Michel"
    fake_data_2[0]["email"] = fake_data[0]["email"]
    fake_data_2[0]["city"] = "Lyon"
    fake_data_2[1]["name"] = "Marcel"
    job.ingest(
        full_table_name=full_table_name,
        dataframe=convert_list_to_dataframe(job, fake_data_2),
    )
    if IS_SPARK_ENVIRONMENT:
        df = job.spark_session.sql(
            f"SELECT * FROM glue_catalog.{job.long_database_prefix}"
            f"{database_name}.{table_prefix}_upsert"
        ).toPandas()
    else:
        df = wr.athena.read_sql_query(
            f"SELECT * FROM {table_prefix}_upsert",
            database=job.long_database_prefix + database_name,
            workgroup=job.athena_workgroup_name,
            boto3_session=job.boto_session,
            ctas_approach=False,
        )
    assert df.shape[0] == 101, f"DF shape is {df.shape[0]} instead of 101"
    assert df[df["name"] == "Michel"].iloc[0]["city"] == "Lyon"
    assert df[df["name"] == "Marcel"].shape[0] == 1


def test_ingest_empty_dataset(
    job: BaseProcessingWrapper, database_name: str, table_prefix: str
):
    full_table_name = f"{database_name}.{table_prefix}_empty_df"
    job.ingest(
        full_table_name=full_table_name, dataframe=convert_list_to_dataframe(job, [])
    )


def main(job: BaseProcessingWrapper):
    """
    The datalake sdk is the real entrypoint of the job,
    which then calls this function
    """
    assert job.task_additional_parameters["hello"] == "world!"
    assert job.task_additional_parameters["other_hello"] == "world!"
    database_name = "datalake_test"
    if IS_SPARK_ENVIRONMENT:
        table_prefix = "test_spark"
    else:
        table_prefix = "test_native"
    # test the installation of custom libraries
    pipeline_utils_main(job.logger)
    test_upsert(job, database_name, table_prefix)
    test_ingest_empty_dataset(job, database_name, table_prefix)
    assert job.perform_table_maintenance(
        f"{database_name}.{table_prefix}_upsert", force_maintenance=True
    )
    return {
        f"{database_name}.{table_prefix}": job.ProcessingResponse(
            dataframe=convert_list_to_dataframe(job, create_fake_data(1000)),
            job_end_message="Hello World!",
        ),
    }
