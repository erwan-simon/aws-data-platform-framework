resource "aws_sfn_state_machine" "main" {
  name     = "${local.environment_name}_${var.pipeline_name}"
  role_arn = aws_iam_role.step_function.arn

  definition = templatefile(var.orchestration_configuration_template_file_path, {
    for task_name, task_configuration in var.tasks_configuration :
    "___${upper(task_name)}_CONFIGURATION___" => task_configuration["infra_type"] == "EMRServerless" ? module.emr_tasks[task_name].step_function_task_configuration : module.ecs_tasks[task_name].step_function_task_configuration
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_function.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}

resource "aws_cloudwatch_log_group" "step_function" {
  name              = "${local.environment_name}_${var.pipeline_name}/step_function"
  retention_in_days = 30
}

resource "aws_iam_role" "step_function" {
  name = "${local.environment_name}_${var.pipeline_name}_step_function"

  assume_role_policy = data.aws_iam_policy_document.step_function_assume.json
}

data "aws_iam_policy_document" "step_function_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "step_function" {
  name   = "${local.environment_name}_${var.pipeline_name}_step_function"
  policy = data.aws_iam_policy_document.step_function.json
}

resource "aws_iam_policy_attachment" "step_function" {
  name       = "${local.environment_name}_${var.pipeline_name}_step_function"
  roles      = [aws_iam_role.step_function.name]
  policy_arn = aws_iam_policy.step_function.arn
}

data "aws_iam_policy_document" "step_function" {
  statement {
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
      "ecs:StopTask",
      "ecs:DescribeTasks",
      "iam:PassRole",
      "emr-serverless:*",
      "ecs:*"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "states:StartExecution"
    ]
    resources = [
      "arn:aws:states:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:stateMachine:${local.environment_name}"
    ]
  }
  statement {
    actions = [
      "states:DescribeExecution",
      "states:StopExecution"
    ]
    resources = [
      "arn:aws:states:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:stateMachine:${local.environment_name}:*"
    ]
  }
  statement {
    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule"
    ]
    resources = [
      "arn:aws:events:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
    ]
  }
}
