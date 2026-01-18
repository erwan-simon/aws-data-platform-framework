output "domain" {
  value = var.domain_object
}

output "pipeline_tasks" {
  value = merge(module.ecs_tasks, module.emr_tasks)
}

output "glue_pipeline_database_name" {
  value = var.skip_pipeline_database_creation ? null : aws_glue_catalog_database.pipeline[0].name
}
