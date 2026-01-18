module "emr_tasks" {
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
