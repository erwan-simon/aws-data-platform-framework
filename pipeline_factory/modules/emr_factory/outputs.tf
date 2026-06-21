output "task_name" {
  value = var.task_name
}

output "step_function_task_configuration" {
  value = trim(jsonencode({
    "Type" : "Task",
    "Resource" : "arn:aws:states:::aws-sdk:emrserverless:startJobRun.waitForTaskToken",
    "Comment" : "https://${var.domain_object.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.domain_object.aws_region}#logsV2:log-groups/log-group/${urlencode(aws_cloudwatch_log_group.main.name)}",
    "Parameters" : {
      "ApplicationId" : aws_emrserverless_application.task.id,
      "Name.$" : "States.UUID()",
      "Tags" : {
        "Appli" : var.domain_object.project_name,
        "Component" : var.domain_object.domain_name,
        "Env" : var.domain_object.stage_name,
        "Name" : "${local.environment_name}_${var.pipeline_name}_${var.task_name}"
      },
      "ExecutionTimeoutMinutes" : var.task_configuration["infra_config"]["job_timeout_minutes"],
      "ConfigurationOverrides" : {
        "MonitoringConfiguration" : {
          "CloudWatchLoggingConfiguration" : {
            "Enabled" : true,
            "LogGroupName" : "${local.environment_name}_${var.pipeline_name}/${var.task_name}"
          }
        }
      },
      "ClientToken.$" : "States.UUID()",
      "ExecutionRoleArn" : aws_iam_role.emr_serverless_task.arn,
      "JobDriver" : {
        "SparkSubmit" : {
          "EntryPoint" : "s3://${aws_s3_object.task_code.bucket}${aws_s3_object.task_code.key}",
          "EntryPointArguments" : [merge({
            "step_function_task_token.$" : "$$.Task.Token",
            "step_function_execution_arn.$" : "$$.Execution.Id",
            # JSON-encoded execution input; the SDK parses it to read optional
            # override keys (e.g. logical_date).
            "step_function_execution_input.$" : "States.JsonToString($$.Execution.Input)",
          }, { for key, value in var.task_configuration["additional_parameters"] : "TASK_ADDITIONAL_PARAMETERS_${key}" => value })],
          "SparkSubmitParameters" : join(" ", [
            "--conf", "spark.executor.cores=${tostring(var.task_configuration["infra_config"]["spark_executor_cores"])}",
            "--conf", "spark.executor.memory=${var.task_configuration["infra_config"]["spark_executor_memory"]}",
            "--conf", "spark.driver.cores=${tostring(var.task_configuration["infra_config"]["spark_driver_cores"])}",
            "--conf", "spark.driver.memory=${var.task_configuration["infra_config"]["spark_driver_memory"]}",
            "--conf", "spark.executor.instances=${tostring(var.task_configuration["infra_config"]["spark_executor_instances"])}",
            "--conf", "spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO",
            "--conf", "spark.sql.catalog.glue_catalog.warehouse=s3://${var.domain_object.technical_bucket_name}/data_catalog/",
            "--conf", "spark.jars=/usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar",
            "--conf", "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
            "--conf", "spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog",
            "--conf", "spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog",
            "--conf", "spark.hadoop.hive.metastore.client.factory.class=com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory",
            "--conf", "spark.dynamicAllocation.executorIdleTimeout=300s", # prevent executors to timeout when they are idle, fixes a bug of EMR serverless
            "--conf", "spark.sql.sources.partitionOverwriteMode=dynamic",
            "--conf", "spark.sql.iceberg.handle-timestamp-without-timezone=true",
            "--conf", "spark.sql.catalog.glue_catalog.cache-enabled=false" # https://github.com/apache/iceberg/issues/3559#issuecomment-970292486
          ])
        }
      }
    }
  }), "{}")
}

output "iam_role_arn" {
  value = aws_iam_role.emr_serverless_task.arn
}

output "failure_cloudwatch_event_pattern" {
  description = "Pattern for cloudwatch event to catch task failure"
  value = {
    "source" : [
      "aws.emr-serverless"
    ],
    "detail-type" : [
      "EMR Serverless Job Run State Change"
    ],
    "detail" : {
      "state" : [
        "FAILED",
        "CANCELLED"
      ],
      "applicationId" : [
        aws_emrserverless_application.task.id
      ]
    }
  }
}

output "task_image_uri" {
  description = "URI of the task Docker image"
  value       = module.image_build_and_upload.image_uri
}
