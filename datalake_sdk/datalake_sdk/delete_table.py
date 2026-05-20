import boto3
import logging
import click


def delete_table(logger: logging.Logger, boto_session: boto3.session.Session,
                 project_name: str, domain_name: str, stage_name: str,
                 short_database_name: str, table_name: str):
    s3_resource = boto_session.resource('s3')
    environment_name = \
        f"{project_name}_{domain_name}_{stage_name}"
    long_database_name = f"{stage_name}_{short_database_name}" \
        if stage_name != "prod" else short_database_name
    data_bucket = s3_resource.Bucket(
        f"{environment_name.replace('_', '-')}-data")
    data_bucket.objects.filter(
        Prefix=f"{long_database_name}/{table_name}").delete()
    logger.info("Deleted data objects...")
    glue_client = boto_session.client("glue")
    glue_client.delete_table(
        DatabaseName=long_database_name, Name=table_name)
    logger.info("Deleted glue table...")


@click.command("delete_table", short_help='Allow to delete a table and all '
               'its data from the datalake')
@click.pass_context
@click.option(
    "-db", '--database-name', required=True,
    help="Database name")
@click.option(
    "-t", '--table-name', required=True,
    help="Database name")
def command_line_delete_table(
        ctx, database_name: str, table_name: str):
    click.confirm(f'You are about to delete the {table_name} table from the ' +
                  f'{database_name} database for the {ctx.obj.stage_name} ' +
                  ' and all its data. Are you SURE you ' +
                  'want to do this?',
                  abort=True)
    delete_table(ctx.obj.logger, ctx.obj.boto_session, ctx.obj.project_name,
                 ctx.obj.domain_name, ctx.obj.stage_name,
                 database_name, table_name)
