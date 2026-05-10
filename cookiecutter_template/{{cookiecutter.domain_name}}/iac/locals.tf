locals {
  stage_name  = terraform.workspace
  domain_name = "{{cookiecutter.domain_name}}"
}
