# Builds and publishes the `shared_lib` Poetry package (../code/shared_lib) to the domain's
# CodeArtifact repository, so every task can `pip install` it via its `requirements.txt`.
# Delete this file (and the matching `additional_rebuild_trigger` + `depends_on` lines in
# pipeline.tf, and the `shared-lib>=...` line from any task's requirements.txt) if you don't
# need a private shared library.

locals {
  shared_lib_version = regex(
    "[0-9]+\\.[0-9]+\\.[0-9]+",
    regex("version[ ]*=[ ]*\"[0-9]+\\.[0-9]+\\.[0-9]+\"", file("${path.root}/../code/shared_lib/pyproject.toml"))
  )
}

module "shared_lib_deploy" {
  source = "git::https://github.com/erwan-simon/terraform-module-build-and-publish-poetry-library-to-codeartifact//iac?ref=v1.0.0"

  code_path                       = "${abspath(path.root)}/../code/shared_lib"
  artifact_repository_endpoint    = module.domain.codeartifact_repository_endpoint
  artifact_repository_domain_name = module.domain.codeartifact_domain_name
}
