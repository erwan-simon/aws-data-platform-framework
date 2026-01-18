module "emr_serverless_application_sandbox" {
  count  = var.skip_emr_serverless_sandbox_creation ? 0 : 1
  source = "../pipeline_factory/modules/emr_factory/"
  domain_object = {
    project_name                     = var.project_name
    domain_name                      = var.domain_name
    git_repository                   = var.git_repository
    role_to_assume_arn               = var.role_to_assume_arn
    stage_name                       = var.stage_name
    datalake_sdk_version             = local.datalake_sdk_version
    datalake_bucket_name             = aws_s3_bucket.data.id
    technical_bucket_name            = aws_s3_bucket.technical.id
    tasks_security_group_id          = aws_security_group.main.id
    failsafe_shutdown_lambda_arn     = aws_lambda_function.failsafe_shutdown.arn
    lakeformation_data_location_arn  = aws_lakeformation_resource.register_data_bucket_location.arn
    domain_glue_database_name        = aws_glue_catalog_database.domain.name
    datalake_admin_principal_arns    = var.datalake_admin_principal_arns
    use_public_subnets               = var.use_public_subnets
    aws_region                       = data.aws_region.current.name
    aws_caller_identity_account_id   = data.aws_caller_identity.current.account_id
    vpc_id                           = data.aws_vpc.main.id
    subnets_list                     = data.aws_subnets.main.ids
    emr_sandbox_image_uri            = "None"
    codeartifact_repository_endpoint = data.aws_codeartifact_repository_endpoint.main.repository_endpoint
  }
  pipeline_name = "main"
  task_name     = "emr_serverless_sandbox"
  task_configuration = {
    infra_type : "",
    type : "",
    path : "${path.module}/sandbox_code",
    infra_config : {
      maximum_capacity_cpu : "60 vCPU",
      maximum_capacity_memory : "120 GB",
      maximum_capacity_disk : "800 GB",
      job_timeout_minutes : 60,
      spark_executor_cores : 4,
      spark_executor_memory : "8g",
      spark_executor_instances : 4,
      spark_driver_cores : 4,
      spark_driver_memory : "8g"
    },
    input_tables : [],
    output_tables : {},
    additional_parameters : {},
    additional_rebuild_trigger : {
      jupyter_notebook_sandbox = filemd5("${path.module}/sandbox_code/emr_serverless/sandbox.ipynb"),
      datalake_sdk_version     = local.datalake_sdk_version
    },
    additional_permissions : null
  }
  role_to_assume_arn     = var.role_to_assume_arn
  dockerfile_path        = abspath("${path.module}/sandbox_code/emr_serverless/")
  pipeline_database_name = aws_glue_catalog_database.domain.name
  package_datalake_sdk   = true
}

resource "aws_lakeformation_permissions" "give_all_access_to_domain_database_for_emr_sandbox_job" {
  count       = var.skip_emr_serverless_sandbox_creation ? 0 : 1
  principal   = module.emr_serverless_application_sandbox[0].iam_role_arn
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.domain.name
  }
}

resource "aws_lakeformation_permissions" "give_all_access_to_domain_tables_for_emr_sandbox_job" {
  count       = var.skip_emr_serverless_sandbox_creation ? 0 : 1
  principal   = module.emr_serverless_application_sandbox[0].iam_role_arn
  permissions = ["ALL"]

  table {
    database_name = aws_glue_catalog_database.domain.name
    wildcard      = true
  }
}

