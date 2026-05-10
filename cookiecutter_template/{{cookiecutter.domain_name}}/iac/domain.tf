data "aws_iam_role" "datalake_admins" {
  for_each = var.datalake_admin_principal_arns == "" ? toset([]) : toset(split(",", var.datalake_admin_principal_arns))
  name     = each.value
}

module "domain" {
  source                               = "{{cookiecutter.domain_factory_source}}"
  project_name                         = var.project_name
  domain_name                          = local.domain_name
  stage_name                           = local.stage_name
  database_description                 = "{{cookiecutter.domain_name}}"
  git_repository                       = var.git_repository
  role_to_assume_arn                   = var.role_to_assume_arn
  datalake_admin_principal_arns        = values(data.aws_iam_role.datalake_admins)[*].arn
  skip_emr_serverless_sandbox_creation = {{cookiecutter.skip_emr_serverless_sandbox_creation}}
  failure_notification_receivers       = split(",", var.failure_notification_receivers)
}
