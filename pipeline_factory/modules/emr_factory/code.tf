locals {
  code_rebuild_trigger = {
    task_parameters = jsonencode({
      "additional_parameters" : var.task_configuration["additional_parameters"],
      "input_tables" : var.task_configuration["input_tables"],
      "output_tables" : var.task_configuration["output_tables"],
      "additional_rebuild_trigger" : var.task_configuration["additional_rebuild_trigger"]
    })
  }
}

module "image_build_and_upload" {
  source               = "../build_and_upload_image_to_ecr"
  environment_name     = local.environment_name
  resources_suffix     = "${replace(var.pipeline_name, "_", "-")}-${replace(var.task_name, "_", "-")}"
  dockerfile_path      = var.dockerfile_path
  role_to_assume_arn   = var.role_to_assume_arn
  source_code_path     = trimsuffix(var.task_configuration["path"], "/")
  rebuild_trigger      = local.code_rebuild_trigger
  domain_object        = var.domain_object
  pipeline_name        = var.pipeline_name
  task_name            = var.task_name
  task_configuration   = var.task_configuration
  package_datalake_sdk = var.package_datalake_sdk
  base_image_uri       = var.domain_object.emr_sandbox_image_uri
}

resource "time_sleep" "wait_for_ecr_to_create" {
  # docker image takes a little while to effectively appear in the ECR after being pushed
  depends_on = [module.image_build_and_upload]
  triggers   = module.image_build_and_upload.rebuild_trigger

  create_duration = "30s"
}

resource "aws_ecr_repository_policy" "emr_serverless_application_access" {
  repository = module.image_build_and_upload.ecr_name
  policy = templatefile("${path.module}/iam_ecr_resource_based_policy_emr_serverless_access.json", {
    "EMR_SERVERLESS_APPLICATION_ARN" : aws_emrserverless_application.task.arn
  })
}
