locals {
  environment_name = "${var.domain_object.project_name}_${var.domain_object.domain_name}_${var.domain_object.stage_name}"
  database_prefix  = var.domain_object.stage_name == "prod" ? "" : "${var.domain_object.stage_name}_"
}
