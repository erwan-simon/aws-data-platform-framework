import importlib.util
import logging
import sys
from types import SimpleNamespace
import click
import boto3

from datalake_sdk.ingestion import command_line_ingest
from datalake_sdk.delete_table import command_line_delete_table
from datalake_sdk.migrate_data import command_line_migrate_data
from datalake_sdk.update_foreign_linked_databases import (
    command_line_update_foreign_linked_databases,
)


@click.group("datalake_sdk")
@click.pass_context
@click.option("-p", "--project-name", required=True, help="Project name")
@click.option("-d", "--domain-name", required=True, help="Domain name")
@click.option("-s", "--stage-name", required=True, help="Stage name")
def command_line_main(ctx, project_name: str, domain_name: str, stage_name: str) -> int:
    ctx.obj = SimpleNamespace(
        logger=logging.getLogger(),
        boto_session=boto3.session.Session(),
        project_name=project_name,
        domain_name=domain_name,
        stage_name=stage_name,
    )
    logging.basicConfig(level=logging.INFO, format="%(message)s")


command_line_main.add_command(command_line_ingest, "ingest")
command_line_main.add_command(command_line_delete_table, "delete_table")
command_line_main.add_command(command_line_migrate_data, "migrate_data")
command_line_main.add_command(
    command_line_update_foreign_linked_databases, "update_foreign_linked_databases"
)

# datalfred subcommand will be available only if strands-agents library is installed (which is done only with extra "agent"
if importlib.util.find_spec("strands"):
    from datalake_sdk.datalfred_agent.main import command_line_datalfred_agent

    command_line_main.add_command(command_line_datalfred_agent, "datalfred")

if __name__ == "__main__":
    sys.exit(command_line_main())
