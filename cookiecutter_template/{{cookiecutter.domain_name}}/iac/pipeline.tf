module "pipeline" {
  source               = "{{cookiecutter.pipeline_factory_source}}"
  domain_object        = module.domain
  pipeline_name        = "{{cookiecutter.pipeline_name}}"
  database_description = "Pipeline of the {{cookiecutter.domain_name}} domain"
  trigger = {
    "type" : "schedule"
    "argument" : "cron(15 1 * * ? *)",
    "parameters" : jsonencode({})
  }
  tasks_configuration = {
    "write_mock_data" : {
      "type" : "python",
      "path" : "pipeline_tasks/write_mock_data",
      "infra_type" : "ECS",
      "infra_config" : {},
      "input_tables" : [],
      "output_tables" : {
        "{{cookiecutter.domain_name}}.mock_data" : {
          "ingestion_mode" : "overwrite"
        }
      }
    },
    "transform" : {
      "type" : "sql",
      "path" : "pipeline_tasks/transform",
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
  orchestration_configuration_template_file_path = "${path.root}/pipeline_tasks/orchestration_configuration.tftpl.json"
  role_to_assume_arn                             = var.role_to_assume_arn
}
