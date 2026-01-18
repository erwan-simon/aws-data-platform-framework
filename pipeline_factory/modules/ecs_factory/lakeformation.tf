resource "aws_lakeformation_permissions" "give_access_to_data_location" {
  principal   = aws_iam_role.ecs_task.arn
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = var.domain_object.lakeformation_data_location_arn
  }
}

resource "aws_lakeformation_permissions" "give_write_access_to_pipeline_database" {
  count       = var.pipeline_database_name == null ? 0 : 1
  principal   = aws_iam_role.ecs_task.arn
  permissions = ["CREATE_TABLE", "ALTER"]

  database {
    name = var.pipeline_database_name
  }
}

resource "aws_lakeformation_permissions" "give_write_access_to_domain_database" {
  principal   = aws_iam_role.ecs_task.arn
  permissions = ["CREATE_TABLE", "ALTER"]

  database {
    name = var.domain_object.domain_glue_database_name
  }
}

resource "aws_lakeformation_permissions" "give_read_access_to_tables_to_read" {
  for_each    = toset(var.task_configuration.input_tables)
  principal   = aws_iam_role.ecs_task.arn
  permissions = ["DESCRIBE", "SELECT"]

  table {
    database_name = "${local.database_prefix}${split(".", each.value)[0]}"
    wildcard      = true # you cannot specify the table itself (split(".", each.value)[1]) because it may not exist yet if it is created by this pipeline
  }
}
