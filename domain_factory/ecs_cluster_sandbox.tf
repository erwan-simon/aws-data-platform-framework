module "ecs_cluster_sandbox" {
  source     = "../pipeline_factory/modules/ecs_factory/"
  depends_on = [terraform_data.docker_validation]
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
    ecs_sandbox_image_uri            = "None"
    codeartifact_repository_endpoint = data.aws_codeartifact_repository_endpoint.main.repository_endpoint
  }
  pipeline_name = "main"
  task_name     = "ecs_sandbox"
  task_configuration = {
    infra_type : "",
    type : "",
    path : "${path.module}/sandbox_code",
    infra_config : {
      "cpu" : "256",
      "memory" : "512"
    },
    input_tables : [],
    output_tables : {},
    additional_parameters : {},
    additional_rebuild_trigger : {
      jupyter_notebook_sandbox = filemd5("${path.module}/sandbox_code/ecs/sandbox.ipynb"),
      datalake_sdk_version     = local.datalake_sdk_version
    },
    additional_permissions : null
  }
  role_to_assume_arn     = var.role_to_assume_arn
  pipeline_database_name = aws_glue_catalog_database.domain.name
  dockerfile_path        = abspath("${path.module}/sandbox_code/ecs/")
  package_datalake_sdk   = true
}

resource "aws_lakeformation_permissions" "give_all_access_to_domain_database_for_ecs_sandbox_job" {
  principal   = module.ecs_cluster_sandbox.iam_role_arn
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.domain.name
  }
}

resource "aws_lakeformation_permissions" "give_all_access_to_domain_tables_for_ecs_sandbox_job" {
  principal   = module.ecs_cluster_sandbox.iam_role_arn
  permissions = ["ALL"]

  table {
    database_name = aws_glue_catalog_database.domain.name
    wildcard      = true
  }
}

