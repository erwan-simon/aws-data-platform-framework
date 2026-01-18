resource "aws_cloudwatch_log_group" "main" {
  name              = "${local.environment_name}_${var.pipeline_name}/${var.task_name}"
  retention_in_days = 30
}
