import click
import logging
import boto3


def update_foreign_linked_databases(
    logger: logging.Logger, boto_session: boto3.session.Session
):
    """
    This script finds the glue data catalog databases and tables shared with current AWS account using LakeFormation and creates a resource link (a Glue Data Catalog database and table in this account) allowing the querrying of said table using Athena and such.

    It also deletes the resource links previously created but which points to a Glue Data Catalog resource which does not exist anymore.
    """
    glue_client = boto_session.client("glue")
    current_account_id = boto_session.client("sts").get_caller_identity().get("Account")
    # list all databases of this account
    all_databases_list = []
    for databases_dict in glue_client.get_paginator("get_databases").paginate(
        ResourceShareType="ALL"
    ):
        all_databases_list.extend(databases_dict["DatabaseList"])
    # databases from another AWS account shared with this account and which does not have an existing resource link in this account
    foreign_databases_missing_linked_database = {}
    # databases which have an existing resource link to a resource which does not exist anymore (deleted since it was shared)
    orphan_linked_databases = {}
    for database_dict in all_databases_list:
        if (
            database_dict["CatalogId"] == current_account_id
            and "TargetDatabase" in database_dict.keys()
        ):
            orphan_linked_databases[database_dict["Name"]] = database_dict
        elif database_dict["CatalogId"] != current_account_id:
            foreign_databases_missing_linked_database[database_dict["Name"]] = (
                database_dict
            )
    for database_dict in all_databases_list:
        database_name = database_dict["Name"]
        if (
            database_name in orphan_linked_databases.keys()
            and database_name in foreign_databases_missing_linked_database
        ):
            orphan_linked_databases.pop(database_name)
            foreign_databases_missing_linked_database.pop(database_name)
    for database_name, database_dict in orphan_linked_databases.items():
        glue_client.delete_database(Name=database_name)
        logger.info(
            f"Deleted orphan database '{database_name}' "
            + f"from foreign account {database_dict['TargetDatabase']['CatalogId']}"
        )
    for (
        database_name,
        database_dict,
    ) in foreign_databases_missing_linked_database.items():
        foreign_database_catalog_id = database_dict["CatalogId"]
        for key_to_remove in ["CreateTime", "CatalogId", "LocationUri", "Description"]:
            if key_to_remove in database_dict:
                database_dict.pop(key_to_remove)
        database_dict["TargetDatabase"] = {
            "CatalogId": foreign_database_catalog_id,
            "DatabaseName": database_name,
            "Region": boto_session.region_name,
        }
        glue_client.create_database(DatabaseInput=database_dict)
        logger.info(
            f"Created linked database '{database_name}' "
            + f"from foreign account {foreign_database_catalog_id}"
        )


@click.command("update_foreign_linked_databases")
@click.pass_context
def command_line_update_foreign_linked_databases(ctx):
    update_foreign_linked_databases(ctx.obj.logger, ctx.obj.boto_session)
