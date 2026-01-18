resource "aws_emrserverless_application" "task" {
  name          = "${local.environment_name}_${var.pipeline_name}_${var.task_name}"
  release_label = "emr-7.1.0"
  type          = "spark"
  auto_start_configuration {
    enabled = true
  }
  auto_stop_configuration {
    enabled              = true
    idle_timeout_minutes = 5
  }

  maximum_capacity {
    cpu    = var.task_configuration["infra_config"]["maximum_capacity_cpu"]
    memory = var.task_configuration["infra_config"]["maximum_capacity_memory"]
    disk   = var.task_configuration["infra_config"]["maximum_capacity_disk"]
  }
  network_configuration {
    subnet_ids         = var.domain_object.subnets_list
    security_group_ids = [var.domain_object.tasks_security_group_id]
  }
  image_configuration {
    image_uri = module.image_build_and_upload.image_uri
  }
  interactive_configuration {
    studio_enabled = true
  }

  tags       = { Name = "${local.environment_name}_${var.pipeline_name}_${var.task_name}" }
  depends_on = [time_sleep.wait_for_ecr_to_create]
}

resource "aws_s3_object" "task_code" {
  bucket = var.domain_object.technical_bucket_name
  key    = "/${var.pipeline_name}/${var.task_name}/entrypoint.py"
  source = "${path.module}/../../../datalake_sdk/datalake_sdk/spark_processing_wrapper.py"
  etag   = filemd5("${abspath(path.module)}/../../../datalake_sdk/datalake_sdk/spark_processing_wrapper.py")
}
