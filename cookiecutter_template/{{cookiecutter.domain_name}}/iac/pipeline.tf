module "pipeline" {
  source               = "{{cookiecutter.pipeline_factory_source}}"
  domain_object        = module.domain
  pipeline_name        = "{{cookiecutter.pipeline_name}}"
  database_description = "Pipeline of the {{cookiecutter.domain_name}} domain"
  trigger = {
    "type" : "schedule"
    "argument" : "cron(15 1 * * ? *)",
    "parameters" : jsonencode({}),
    "start_disabled" : true,
  }
  tasks_configuration = {
    "write_mock_data" : {
      "type" : "python",
      "path" : "{{cookiecutter.pipeline_name}}/write_mock_data",
      "infra_type" : "ECS",
      "infra_config" : {},
      "input_tables" : [],
      "output_tables" : {
        "{{cookiecutter.domain_name}}.mock_data" : {
          "ingestion_mode" : "overwrite"
        }
      }
      # Rebuilds the task image when the shared library version bumps — keep this in sync
      # with the version pinned in this task's requirements.txt.
      "additional_rebuild_trigger" : {
        "shared_lib_version" : local.shared_lib_version
      }
    },
    "transform" : {
      "type" : "sql",
      "path" : "{{cookiecutter.pipeline_name}}/transform",
      "infra_type" : "ECS",
      "infra_config" : {},
      "input_tables" : [
        "{{cookiecutter.domain_name}}.mock_data"
      ],
      "output_tables" : {
        "{{cookiecutter.domain_name}}.mock_data_transformed" : {
          "ingestion_mode" : "overwrite"
        }
      }
    }
  }
  orchestration_configuration_template_file_path = "${path.root}/{{cookiecutter.pipeline_name}}/orchestration_configuration.tftpl.json"
  role_to_assume_arn                             = var.role_to_assume_arn

  # Ensures the shared library wheel is published to CodeArtifact before the task image is
  # built (the build runs `pip install shared-lib` from that repo).
  depends_on = [module.shared_lib_deploy]
}
