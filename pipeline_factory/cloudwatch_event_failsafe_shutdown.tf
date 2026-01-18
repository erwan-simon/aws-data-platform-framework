resource "aws_cloudwatch_event_rule" "tasks_failure" {
  for_each = {
    for task_name, task_configuration in var.tasks_configuration :
    task_name => task_configuration["infra_type"] == "EMRServerless" ? module.emr_tasks[task_name].failure_cloudwatch_event_pattern : module.ecs_tasks[task_name].failure_cloudwatch_event_pattern
  }
  name          = length("${local.environment_name}_${var.pipeline_name}_${each.key}_failure") > 64 ? "${substr("${local.environment_name}_${var.pipeline_name}_${each.key}_failure", 0, 54)}_${substr(sha1("${local.environment_name}_${var.pipeline_name}_${each.key}_failure"), 0, 9)}" : "${local.environment_name}_${var.pipeline_name}_${each.key}_failure"
  description   = "Capture the event of the ${each.key} task failing"
  event_pattern = jsonencode(each.value)
  tags = {
    Name = "${local.environment_name}_${var.pipeline_name}_${each.key}_failure"
  }
}

resource "time_sleep" "wait_for_cloudwatch_event_rule_to_create" {
  create_duration = "30s"
  depends_on      = [aws_cloudwatch_event_rule.tasks_failure]
}

resource "aws_cloudwatch_event_target" "tasks_failure" {
  for_each   = toset([for task_name in keys(var.tasks_configuration) : task_name])
  rule       = aws_cloudwatch_event_rule.tasks_failure[each.key].name
  target_id  = "${local.environment_name}_${var.pipeline_name}_${each.key}"
  arn        = var.domain_object.failsafe_shutdown_lambda_arn
  depends_on = [time_sleep.wait_for_cloudwatch_event_rule_to_create]
}

resource "aws_lambda_permission" "allow_cloudwatch_to_trigger_lambda" {
  for_each      = toset([for task_name in keys(var.tasks_configuration) : task_name])
  statement_id  = "${local.environment_name}_${var.pipeline_name}_${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = var.domain_object.failsafe_shutdown_lambda_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.tasks_failure[each.key].arn
}
