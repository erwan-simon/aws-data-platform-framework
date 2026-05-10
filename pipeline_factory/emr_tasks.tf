resource "terraform_data" "emr_sandbox_image_check" {
  for_each = toset([for task_name, task_configuration in var.tasks_configuration : task_name if task_configuration["infra_type"] == "EMRServerless"])

  lifecycle {
    precondition {
      condition     = var.domain_object.emr_sandbox_image_uri != null
      error_message = "Pipeline '${var.pipeline_name}' contains an EMRServerless task ('${each.key}') but the domain '${var.domain_object.domain_name}' was deployed with skip_emr_serverless_sandbox_creation = true. Set skip_emr_serverless_sandbox_creation = false on the domain_factory module and redeploy the domain before adding EMRServerless tasks."
    }
  }
}

module "emr_tasks" {
  depends_on             = [terraform_data.emr_sandbox_image_check]
  for_each               = toset([for task_name, task_configuration in var.tasks_configuration : task_name if task_configuration["infra_type"] == "EMRServerless"])
  source                 = "./modules/emr_factory/"
  domain_object          = var.domain_object
  pipeline_name          = var.pipeline_name
  task_name              = each.key
  task_configuration     = var.tasks_configuration[each.key]
  dockerfile_path        = abspath("${path.module}/modules/emr_factory/")
  role_to_assume_arn     = var.role_to_assume_arn
  pipeline_database_name = var.skip_pipeline_database_creation ? null : aws_glue_catalog_database.pipeline[0].name
  package_datalake_sdk   = false
}
