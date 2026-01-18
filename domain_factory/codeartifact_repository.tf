resource "aws_codeartifact_repository" "main" {
  repository = replace(local.environment_name, "_", "-")
  domain     = var.project_name
}
