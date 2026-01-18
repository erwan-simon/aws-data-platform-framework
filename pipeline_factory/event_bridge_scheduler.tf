resource "aws_scheduler_schedule_group" "main" {
  count = var.trigger["type"] == "schedule" ? 1 : 0
  name  = "${local.environment_name}_${var.pipeline_name}"
}

resource "aws_scheduler_schedule" "step_function_scheduled_trigger" {
  count      = var.trigger["type"] == "schedule" ? 1 : 0
  name       = "${local.environment_name}_${var.pipeline_name}_trigger"
  group_name = aws_scheduler_schedule_group.main[0].name
  state      = "ENABLED"
  start_date = timeadd(timestamp(), "10m")

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.trigger["argument"]
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_sfn_state_machine.main.arn
    role_arn = aws_iam_role.eventbridge_trigger[0].arn
    retry_policy {
      maximum_retry_attempts = 0
    }
    input = var.trigger["parameters"]
  }
}

resource "aws_iam_role" "eventbridge_trigger" {
  count = var.trigger["type"] == "schedule" ? 1 : 0
  name  = "${local.environment_name}_${var.pipeline_name}_eventbridge_trigger"

  assume_role_policy = data.aws_iam_policy_document.eventbridge_trigger_assume[0].json
}

data "aws_iam_policy_document" "eventbridge_trigger_assume" {
  count = var.trigger["type"] == "schedule" ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "eventbridge_trigger" {
  count  = var.trigger["type"] == "schedule" ? 1 : 0
  name   = "${local.environment_name}_${var.pipeline_name}_eventbridge_trigger"
  policy = data.aws_iam_policy_document.eventbridge_trigger[0].json
}

resource "aws_iam_policy_attachment" "eventbridge_trigger" {
  count      = var.trigger["type"] == "schedule" ? 1 : 0
  name       = "${local.environment_name}_${var.pipeline_name}_eventbridge_trigger"
  roles      = [aws_iam_role.eventbridge_trigger[0].name]
  policy_arn = aws_iam_policy.eventbridge_trigger[0].arn
}

data "aws_iam_policy_document" "eventbridge_trigger" {
  count = var.trigger["type"] == "schedule" ? 1 : 0
  statement {
    actions = [
      "iam:PassRole"
    ]
    resources = [aws_sfn_state_machine.main.arn]
    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values   = ["states.amazonaws.com"]
    }
  }
  statement {
    actions = [
      "states:StartExecution"
    ]
    resources = [
      aws_sfn_state_machine.main.arn
    ]
  }
}
