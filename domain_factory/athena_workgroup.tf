resource "aws_athena_workgroup" "main" {
  name = local.environment_name

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.technical.bucket}/${local.athena_workgroup_output_key}"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
