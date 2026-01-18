output "codeartifact_repository_name" {
  value = aws_codeartifact_repository.main.repository
}

output "codeartifact_domain_name" {
  value = aws_codeartifact_repository.main.domain
}

output "codeartifact_repository_endpoint" {
  value = data.aws_codeartifact_repository_endpoint.main.repository_endpoint
}

output "datalake_sdk_version" {
  value = local.datalake_sdk_version
}

output "datalake_bucket_name" {
  value = aws_s3_bucket.data.id
}

output "technical_bucket_name" {
  value = aws_s3_bucket.technical.id
}

output "project_name" {
  value = var.project_name
}

output "domain_name" {
  value = var.domain_name
}

output "stage_name" {
  value = var.stage_name
}

output "git_repository" {
  value = var.git_repository
}

output "role_to_assume_arn" {
  value = var.role_to_assume_arn
}

output "tasks_security_group_id" {
  value = aws_security_group.main.id
}

output "athena_workgroup_name" {
  value = aws_athena_workgroup.main.name
}

output "failsafe_shutdown_lambda_arn" {
  value = aws_lambda_function.failsafe_shutdown.arn
}

output "lakeformation_data_location_arn" {
  value = aws_lakeformation_resource.register_data_bucket_location.arn
}

output "domain_glue_database_name" {
  value = aws_glue_catalog_database.domain.name
}

output "datalake_admin_principal_arns" {
  value = var.datalake_admin_principal_arns
}

output "use_public_subnets" {
  value = var.use_public_subnets
}

output "vpc_id" {
  value = data.aws_vpc.main.id
}

output "subnets_list" {
  value = data.aws_subnets.main.ids
}

output "aws_caller_identity_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  value = data.aws_region.current.name
}

output "ecs_sandbox_image_uri" {
  value = module.ecs_cluster_sandbox.task_image_uri
}

output "emr_sandbox_image_uri" {
  value = var.skip_emr_serverless_sandbox_creation ? null : module.emr_serverless_application_sandbox[0].task_image_uri
}

output "failure_notification_receivers" {
  value = var.failure_notification_receivers
}
