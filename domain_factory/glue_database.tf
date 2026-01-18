# glue database shared by the whole domains, which means available for all pipelines
resource "aws_glue_catalog_database" "domain" {
  name         = var.stage_name == "prod" ? var.domain_name : "${var.stage_name}_${var.domain_name}"
  location_uri = "s3://${aws_s3_bucket.data.id}/${var.domain_name}/"
  lifecycle {
    prevent_destroy = true
  }
  description = var.database_description
}

resource "aws_lakeformation_permissions" "give_all_access_to_domain_database_for_datalake_admins" {
  for_each    = toset(var.datalake_admin_principal_arns)
  principal   = each.value
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.domain.name
  }
}

resource "aws_lakeformation_permissions" "give_all_access_to_domain_tables_for_datalake_admins" {
  for_each    = toset(var.datalake_admin_principal_arns)
  principal   = each.value
  permissions = ["ALL"]

  table {
    database_name = aws_glue_catalog_database.domain.name
    wildcard      = true
  }
}

