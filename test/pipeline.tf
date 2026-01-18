module "integration_tests_pipeline" {
  source               = "../pipeline_factory/"
  domain_object        = module.domain
  pipeline_name        = "tests"
  database_description = "Main pipeline of the integration tests"
  trigger = {
    "type" : "schedule"
    "argument" : "cron(15 1 * * ? *)",
    "parameters" : jsonencode({
      "hello" : "world!"
    })
  }
  tasks_configuration = {
    "test_native_write" : {
      "type" : "python",
      "path" : "integration_tests_pipeline/test_write",
      "infra_type" : "ECS",
      "infra_config" : {},
      "input_tables" : [],
      "output_tables" : {
        "datalake_test.test_native" : {
          "ingestion_mode" : "overwrite"
        },
        "datalake_test.test_native_upsert" : {
          "ingestion_mode" : "upsert",
          "upsert_keys" : ["name", "email"]
        },
      }
      "additional_permissions" : data.aws_iam_policy_document.additional_permissions.json,
      "additional_rebuild_trigger" : {
        "utils_library_version" : local.utils_library_version
      },
      "additional_parameters" : {
        "hello.$" : "$.hello", # reference the "hello" key in trigger parameters, expects a "world!" as value
        "other_hello" : "world!"
      }
    },
    "test_native_sql_entrypoint" : {
      "type" : "sql",
      "path" : "integration_tests_pipeline/test_native_sql_entrypoint",
      "infra_type" : "ECS",
      "infra_config" : {},
      "input_tables" : [
        "datalake_test.test_native"
      ],
      "output_tables" : {
        "datalake_test.test_native_sql_entrypoint" : {
          "ingestion_mode" : "overwrite"
        }
      }
    },
    "test_spark_write" : {
      "type" : "python",
      "path" : "integration_tests_pipeline/test_write",
      "infra_type" : "EMRServerless",
      "infra_config" : {},
      "input_tables" : [],
      "output_tables" : {
        "datalake_test.test_spark" : {
          "ingestion_mode" : "overwrite"
        },
        "datalake_test.test_spark_upsert" : {
          "ingestion_mode" : "upsert",
          "upsert_keys" : ["name", "email"]
        },
      }
      "additional_permissions" : data.aws_iam_policy_document.additional_permissions.json
      "additional_rebuild_trigger" : {
        "utils_library_version" : local.utils_library_version
      },
      "additional_parameters" : {
        "hello.$" : "$.hello",   # reference the "hello" key in trigger parameters, expects a "world!" as value
        "other_hello" : "world!" # test non dynamic argument
      }
    },
    "test_spark_sql_entrypoint" : {
      "type" : "sql",
      "path" : "integration_tests_pipeline/test_spark_sql_entrypoint",
      "infra_type" : "EMRServerless",
      "infra_config" : {},
      "input_tables" : [
        "datalake_test.test_spark"
      ],
      "output_tables" : {
        "datalake_test.test_spark_sql_entrypoint" : {
          "ingestion_mode" : "overwrite"
        }
      }
    },
    "check_and_clean" : {
      "type" : "python",
      "path" : "integration_tests_pipeline/check_and_clean",
      "infra_type" : "ECS",
      "infra_config" : {},
      "input_tables" : [
        "datalake_test.test_spark_sql_entrypoint",
        "datalake_test.test_native_sql_entrypoint"
      ],
      "output_tables" : {},
    },
  }
  orchestration_configuration_template_file_path = "${path.root}/integration_tests_pipeline/orchestration_configuration.tftpl.json"
  role_to_assume_arn                             = var.role_to_assume_arn
  depends_on                                     = [module.pipeline_utils_deploy]
}
