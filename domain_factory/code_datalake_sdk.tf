module "datalake_sdk_deploy" {
  source = "git::https://github.com/erwan-simon/terraform-module-build-and-publish-poetry-library-to-codeartifact//iac?ref=v1.0.0"

  code_path                       = "${abspath(path.module)}/../datalake_sdk/"
  artifact_repository_domain_name = var.project_name
  artifact_repository_endpoint    = data.aws_codeartifact_repository_endpoint.main.repository_endpoint
}
