output "task_name" {
  value = var.task_name
}

output "step_function_task_configuration" {
  value = trim(jsonencode({
    "Type" : "Task",
    "Resource" : "arn:aws:states:::aws-sdk:ecs:runTask.waitForTaskToken",
    "Comment" : "https://${var.domain_object.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.domain_object.aws_region}#logsV2:log-groups/log-group/${urlencode(aws_cloudwatch_log_group.main.name)}",
    "Parameters" : {
      "LaunchType" : "FARGATE",
      "Cluster" : aws_ecs_cluster.main.arn,
      "TaskDefinition" : aws_ecs_task_definition.main.arn_without_revision,
      "ClientToken.$" : "States.UUID()",
      "PropagateTags" : "TASK_DEFINITION",
      "Overrides" : {
        "ContainerOverrides" : [{
          "Name" : module.image_build_and_upload.ecr_name,
          "Environment" : concat([{
            "Name" : "step_function_task_token",
            "Value.$" : "$$.Task.Token"
            },
            {
              "Name" : "step_function_execution_arn",
              "Value.$" : "$$.Execution.Id"
              }], [for key, value in var.task_configuration["additional_parameters"] : {
              "Name" : "TASK_ADDITIONAL_PARAMETERS_${trimsuffix(key, ".$")}",
              "Value${endswith(key, ".$") ? ".$" : ""}" : value
          }])
        }]
      },
      "NetworkConfiguration" : {
        "AwsvpcConfiguration" : {
          "Subnets" : var.domain_object.subnets_list,
          "SecurityGroups" : [var.domain_object.tasks_security_group_id],
          "AssignPublicIp" : var.domain_object.use_public_subnets ? "ENABLED" : "DISABLED"
        }
      }
    }
  }), "{}")
}

output "iam_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "failure_cloudwatch_event_pattern" {
  description = "Pattern for cloudwatch event to catch task failure"
  value = {
    "source" : [
      "aws.ecs"
    ],
    "detail-type" : [
      "ECS Task State Change"
    ],
    "detail" : {
      "lastStatus" : [
        "STOPPED"
      ],
      "clusterArn" : [
        aws_ecs_cluster.main.arn
      ],
      "taskDefinitionArn" : [
        aws_ecs_task_definition.main.arn
      ]
    }
  }
}

output "task_image_uri" {
  description = "URI of the task Docker image"
  value       = module.image_build_and_upload.image_uri
}
