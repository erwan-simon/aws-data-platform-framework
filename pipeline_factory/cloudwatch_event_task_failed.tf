resource "aws_cloudwatch_event_rule" "step_function_failed" {
  name        = "${local.environment_name}_${var.pipeline_name}_failure"
  description = "Capture the event of the step function failing"

  event_pattern = jsonencode({
    "source" : [
      "aws.states"
    ],
    "detail-type" : [
      "Step Functions Execution Status Change"
    ],
    "detail" : {
      "status" : [
        "FAILED",
        "ABORTED"
      ],
      "stateMachineArn" : [
        aws_sfn_state_machine.main.arn
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "step_function_failed" {
  rule      = aws_cloudwatch_event_rule.step_function_failed.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alerting_step_function_failed.arn
}

resource "aws_sns_topic" "alerting_step_function_failed" {
  name = "${local.environment_name}_${var.pipeline_name}_failure"
}

resource "aws_sns_topic_policy" "alerting_step_function_failed" {
  arn    = aws_sns_topic.alerting_step_function_failed.arn
  policy = data.aws_iam_policy_document.sns_topic_alerting_step_function_failed.json
}

data "aws_iam_policy_document" "sns_topic_alerting_step_function_failed" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.alerting_step_function_failed.arn]
  }
}

resource "aws_sns_topic_subscription" "alerting_step_function_failed_email_target" {
  for_each  = toset(var.domain_object.failure_notification_receivers)
  topic_arn = aws_sns_topic.alerting_step_function_failed.arn
  protocol  = "email"
  endpoint  = each.value
}
