import os
import click


@click.command("ingest", short_help='Allow to ingest in the datalake')
@click.pass_context
@click.option(
    "-db", '--database-name', required=True,
    help="Short database name (not including environment name)")
@click.option(
    "-t", '--table-name', required=True,
    help="Name of the table")
@click.option(
    "-f", '--input-file-path', required=True,
    help="Path of the input file to ingest, should be csv or parquet")
@click.option(
    "-m", '--ingestion-mode', required=True,
    help="Mode of the ingestion, should be overwrite, append or upsert")
@click.option(
    "-uk", '--upsert-keys', required=False, default="",
    help="List of the columns used to know if the row should be updated or " +
    "inserted by the upsert, separated by a slash")
@click.option(
    "-pk", '--partition-keys', required=False, default="",
    help="List of the columns to use as partition keys, separated by a slash")
@click.option(
    '--use-spark', required=False, is_flag=True,
    help="If set this ingestion will use the spark ingestion")
@click.option(
    '--csv-delimiter', required=False, default=",",
    help="Delimiter char used if file is csv. Default is a coma")
def command_line_ingest(
        ctx, database_name: str, table_name: str, input_file_path: str,
        ingestion_mode: str, upsert_keys: str = None,
        partition_keys: str = None,
        use_spark: bool = False,
        csv_delimiter: str = ","):
    os.environ["PROJECT_NAME"] = ctx.obj.project_name
    os.environ["DOMAIN_NAME"] = ctx.obj.domain_name
    os.environ["STAGE_NAME"] = ctx.obj.stage_name
    os.environ["PIPELINE_NAME"] = ""
    os.environ["TASK_NAME"] = ""
    os.environ["IS_SQL_JOB"] = "false"
    if use_spark:
        from datalake_sdk.spark_processing_wrapper \
            import SparkProcessingWrapper as wrapper_class
    else:
        from datalake_sdk.native_python_processing_wrapper \
            import NativePythonProcessingWrapper as wrapper_class
    wrapper_instance = wrapper_class(
        output_tables={
            f"{database_name}.{table_name}": {
                "upsert_keys": upsert_keys.split("/") if upsert_keys else [],
                "partition_keys": partition_keys.split("/")
                if partition_keys else [],
                "ingestion_mode": ingestion_mode
            }
        })
    ctx.obj.logger.info("Finished init of datalake_sdk, reading dataset to ingest...")
    input_dataframe = wrapper_instance.read_input_dataset(
        input_file_path, csv_delimiter)
    ctx.obj.logger.info("Finished reading dataset to ingest, begining ingestion...")
    wrapper_instance.ingest(f"{database_name}.{table_name}", input_dataframe)
