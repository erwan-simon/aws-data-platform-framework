# Builds and publishes a Poetry library to CodeArtifact. Kept here primarily as the integration-test fixture that proves "additional_rebuild_trigger + a private wheel pulled by tasks" works end-to-end. Delete if your pipeline doesn't need a private library.
locals {
  utils_library_version = regex("[0-9]+.[0-9]+.[0-9]+", regex("version[ ]*=[ ]*\"[0-9]+.[0-9]+.[0-9]+\"", file("${path.root}/utils/pyproject.toml")))
}

module "pipeline_utils_deploy" {
  source = "git::https://github.com/erwan-simon/terraform-module-build-and-publish-poetry-library-to-codeartifact//iac?ref=v1.1.1"

  code_path                       = "${abspath(path.root)}/utils"
  artifact_repository_endpoint    = module.domain.codeartifact_repository_endpoint
  artifact_repository_domain_name = module.domain.codeartifact_domain_name
}
