locals {
  environment_name            = "${var.project_name}_${var.domain_name}_${var.stage_name}"
  athena_workgroup_output_key = "athena_results/"
  datalake_sdk_version        = regex("[0-9]+.[0-9]+.[0-9]+", regex("version[ ]*=[ ]*\"[0-9]+.[0-9]+.[0-9]+\"", file("${path.module}/../datalake_sdk/pyproject.toml")))
  codeartifact_repository_url = "${aws_codeartifact_repository.main.domain}-${data.aws_caller_identity.current.account_id}.d.codeartifact.${data.aws_region.current.name}.amazonaws.com/pypi/${aws_codeartifact_repository.main.repository}/simple/"
}
