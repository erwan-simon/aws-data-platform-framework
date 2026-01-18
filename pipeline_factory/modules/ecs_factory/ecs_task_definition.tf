resource "aws_ecs_task_definition" "main" {
  family                   = "${local.environment_name}_${var.pipeline_name}_${var.task_name}"
  container_definitions    = <<DEFINITION
    [
      {
        "name": "${module.image_build_and_upload.ecr_name}",
        "image": "${module.image_build_and_upload.image_uri}",
        "essential": true,
        "cpu": ${var.task_configuration["infra_config"]["cpu"]},
        "memory": ${var.task_configuration["infra_config"]["memory"]},
        "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
            "awslogs-group": "${aws_cloudwatch_log_group.main.name}",
            "awslogs-region": "${var.domain_object.aws_region}",
            "awslogs-stream-prefix": "ecs"
          }
        }
      }
    ]
    DEFINITION
  cpu                      = var.task_configuration["infra_config"]["cpu"]
  execution_role_arn       = aws_iam_role.ecs_task.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  memory                   = var.task_configuration["infra_config"]["memory"]
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}
