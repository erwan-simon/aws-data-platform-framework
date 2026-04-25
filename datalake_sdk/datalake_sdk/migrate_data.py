import math
import os

import click
import awswrangler as wr


def _copy_table(
    wrapper_instance,
    logger,
    boto_session,
    workgroup: str,
    source_long_database_name: str,
    target_long_database_name: str,
    source_table_name: str,
    target_table_name: str,
    full_target_table_name: str,
    chunk_size: int,
):
    source_count = wr.athena.read_sql_query(
        sql=f'SELECT COUNT(*) AS row_count FROM "{source_table_name}"',
        database=source_long_database_name,
        ctas_approach=False,
        unload_approach=False,
        workgroup=workgroup,
        boto3_session=boto_session,
    )["row_count"].iloc[0]
    num_chunks = max(1, math.ceil(source_count / chunk_size))
    logger.info(
        f"[{source_table_name}] {source_count} rows -> "
        f"{num_chunks} chunk(s) of {chunk_size}"
    )

    chunks = wr.athena.read_sql_query(
        sql=f'SELECT * FROM "{source_table_name}"',
        database=source_long_database_name,
        ctas_approach=False,
        unload_approach=False,
        chunksize=chunk_size,
        workgroup=workgroup,
        boto3_session=boto_session,
    )
    for index, chunk in enumerate(chunks):
        wrapper_instance.ingest(full_target_table_name, chunk)
        logger.info(f"[{source_table_name}] Copied chunk {index + 1}/{num_chunks}")

    target_count = wr.athena.read_sql_query(
        sql=f'SELECT COUNT(*) AS n FROM "{target_table_name}"',
        database=target_long_database_name,
        ctas_approach=False,
        unload_approach=False,
        workgroup=workgroup,
        boto3_session=boto_session,
    ).iloc[0, 0]
    logger.info(f"[{source_table_name}] Source: {source_count}, Target: {target_count}")
    if source_count != target_count:
        logger.warning(
            f"[{source_table_name}] Row count mismatch between source "
            f"({source_count}) and target ({target_count}). This can be "
            "expected in 'upsert' mode if the source contains duplicate keys."
        )


@click.command(
    "migrate_data",
    short_help="Copy data from one stage of a table (or full DB) to another (e.g. prod -> dev)",
)
@click.pass_context
@click.option(
    "-ss",
    "--source-stage-name",
    required=True,
    help="Stage to read data from (e.g. prod). The target stage is the global -s/--stage-name.",
)
@click.option(
    "-db",
    "--database-name",
    required=True,
    help="Short database name (not including environment name)",
)
@click.option(
    "-st",
    "--source-table-name",
    required=False,
    default=None,
    help="Name of the table to read from in the source stage. "
    "If omitted, every table of the source database is replicated to the target database with the same name.",
)
@click.option(
    "-tt",
    "--target-table-name",
    required=False,
    default=None,
    help="Name of the table to write to in the target stage. "
    "Defaults to the source table name. Only valid when --source-table-name is provided.",
)
@click.option(
    "-uk",
    "--upsert-keys",
    required=False,
    default="",
    help="Slash-separated list of upsert key columns (only used with ingestion-mode=upsert). "
    "Applied to every table when copying a full database.",
)
@click.option(
    "-pk",
    "--partition-keys",
    required=False,
    default="",
    help="Slash-separated list of partition key columns. "
    "Applied to every table when copying a full database.",
)
@click.option(
    "--chunk-size",
    required=False,
    default=200_000,
    type=int,
    help="Number of rows per Athena read chunk",
)
def command_line_migrate_data(
    ctx,
    source_stage_name: str,
    database_name: str,
    source_table_name: str,
    target_table_name: str,
    upsert_keys: str,
    partition_keys: str,
    chunk_size: int,
):
    target_stage_name = ctx.obj.stage_name
    if source_stage_name == target_stage_name:
        raise click.UsageError(
            "Source and target stages must be different "
            f"(both are '{source_stage_name}')."
        )
    if target_table_name and not source_table_name:
        raise click.UsageError(
            "--target-table-name can only be used together with --source-table-name."
        )

    os.environ["PROJECT_NAME"] = ctx.obj.project_name
    os.environ["DOMAIN_NAME"] = ctx.obj.domain_name
    os.environ["STAGE_NAME"] = target_stage_name
    os.environ["PIPELINE_NAME"] = ""
    os.environ["TASK_NAME"] = ""
    os.environ["IS_SQL_JOB"] = "false"

    source_long_database_name = (
        f"{source_stage_name}_{database_name}"
        if source_stage_name != "prod"
        else database_name
    )
    target_long_database_prefix = (
        f"{target_stage_name}_" if target_stage_name != "prod" else ""
    )
    target_long_database_name = f"{target_long_database_prefix}{database_name}"
    logger = ctx.obj.logger
    boto_session = ctx.obj.boto_session

    if source_table_name:
        target_table_name = target_table_name or source_table_name
        tables_to_copy = [(source_table_name, target_table_name)]
    else:
        glue_client = boto_session.client("glue")
        tables_to_copy = []
        paginator = glue_client.get_paginator("get_tables")
        for response in paginator.paginate(DatabaseName=source_long_database_name):
            for table_dict in response.get("TableList", []):
                tables_to_copy.append((table_dict["Name"], table_dict["Name"]))
        if not tables_to_copy:
            raise click.UsageError(
                f"No tables found in source database '{source_long_database_name}'."
            )

    tables_summary = ", ".join(
        f"{src}->{tgt}" if src != tgt else src for src, tgt in tables_to_copy
    )
    click.confirm(
        f"You are about to copy {len(tables_to_copy)} table(s) from "
        f"{source_long_database_name} ({source_stage_name}) to "
        f"{target_long_database_name} ({target_stage_name}): "
        f"{tables_summary}. "
        "Are you sure you want to do this?",
        abort=True,
    )

    from datalake_sdk.native_python_processing_wrapper import (
        NativePythonProcessingWrapper,
    )

    output_tables = {
        f"{database_name}.{tgt}": {
            "upsert_keys": upsert_keys.split("/") if upsert_keys else [],
            "partition_keys": partition_keys.split("/") if partition_keys else [],
            "ingestion_mode": "upsert",
        }
        for _, tgt in tables_to_copy
    }
    wrapper_instance = NativePythonProcessingWrapper(output_tables=output_tables)
    workgroup = wrapper_instance.athena_workgroup_name

    for src, tgt in tables_to_copy:
        full_target_table_name = f"{database_name}.{tgt}"
        logger.info(f"=== Copying {src} -> {tgt} ===")
        _copy_table(
            wrapper_instance=wrapper_instance,
            logger=logger,
            boto_session=boto_session,
            workgroup=workgroup,
            source_long_database_name=source_long_database_name,
            target_long_database_name=target_long_database_name,
            source_table_name=src,
            target_table_name=tgt,
            full_target_table_name=full_target_table_name,
            chunk_size=chunk_size,
        )
    logger.info("Iceberg copy finished")
