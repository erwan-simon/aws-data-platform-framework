resource "aws_glue_catalog_database" "pipeline" {
  count        = var.skip_pipeline_database_creation ? 0 : 1
  name         = var.domain_object.stage_name == "prod" ? "${var.domain_object.domain_name}_${var.pipeline_name}" : "${var.domain_object.stage_name}_${var.domain_object.domain_name}_${var.pipeline_name}"
  location_uri = "s3://${var.domain_object.datalake_bucket_name}/${var.domain_object.domain_name}_${var.pipeline_name}/"
  lifecycle {
    prevent_destroy = true
  }
  description = var.database_description
}

resource "aws_lakeformation_permissions" "give_all_access_to_pipeline_database_for_datalake_admins" {
  for_each    = var.skip_pipeline_database_creation ? [] : toset(var.domain_object.datalake_admin_principal_arns)
  principal   = each.value
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.pipeline[0].name
  }
}

resource "aws_lakeformation_permissions" "give_all_access_to_pipeline_tables_for_datalake_admins" {
  for_each    = var.skip_pipeline_database_creation ? [] : toset(var.domain_object.datalake_admin_principal_arns)
  principal   = each.value
  permissions = ["ALL"]

  table {
    database_name = aws_glue_catalog_database.pipeline[0].name
    wildcard      = true
  }
}

