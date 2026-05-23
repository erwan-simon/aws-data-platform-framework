module "build_failsafe_shutdown_lambda_docker_image" {
  source = "../pipeline_factory/modules/build_and_upload_image_to_ecr"

  source_code_path = "${path.module}/lambda/failsafe_shutdown_code/"
  domain_object = {
    project_name                     = var.project_name
    domain_name                      = var.domain_name
    git_repository                   = var.git_repository
    role_to_assume_arn               = var.role_to_assume_arn
    stage_name                       = var.stage_name
    datalake_sdk_version             = local.datalake_sdk_version
    datalake_bucket_name             = aws_s3_bucket.data.id
    technical_bucket_name            = aws_s3_bucket.technical.id
    tasks_security_group_id          = aws_security_group.main.id
    failsafe_shutdown_lambda_arn     = ""
    lakeformation_data_location_arn  = aws_lakeformation_resource.register_data_bucket_location.arn
    domain_glue_database_name        = aws_glue_catalog_database.domain.name
    datalake_admin_principal_arns    = var.datalake_admin_principal_arns
    use_public_subnets               = var.use_public_subnets
    aws_region                       = data.aws_region.current.name
    aws_caller_identity_account_id   = data.aws_caller_identity.current.account_id
    vpc_id                           = data.aws_vpc.main.id
    subnets_list                     = data.aws_subnets.main.ids
    ecs_sandbox_image_uri            = "None"
    codeartifact_repository_endpoint = data.aws_codeartifact_repository_endpoint.main.repository_endpoint
  }
  dockerfile_path = abspath("${path.module}/lambda/failsafe_shutdown_code/")
  pipeline_name   = "main"
  task_name       = "failsafe_shutdown"
  task_configuration = {
    infra_type : "",
    type : "",
    path : "${path.module}/lambda/failsafe_shutdown_code/",
    infra_config : {},
    input_tables : [],
    output_tables : {},
    additional_parameters : {},
    additional_rebuild_trigger : {},
    additional_permissions : null
  }
  package_datalake_sdk = true
  role_to_assume_arn   = ""
  resources_suffix     = "failsafe_shutdown"
  environment_name     = local.environment_name
  rebuild_trigger = {
    "datalake_sdk_version" : local.datalake_sdk_version
  }
}

resource "aws_lambda_function" "failsafe_shutdown" {
  function_name = "${local.environment_name}_failsafe_shutdown"
  role          = aws_iam_role.lambda_failsafe_shutdown.arn

  package_type = "Image"
  image_uri    = module.build_failsafe_shutdown_lambda_docker_image.image_uri
  timeout      = 300
  memory_size  = 520

  environment {
    variables = {
      PROJECT_NAME                     = var.project_name
      DOMAIN_NAME                      = var.domain_name
      STAGE_NAME                       = var.stage_name
      LLM_ENABLED                      = tostring(var.enable_llm)
      FAILURE_INVESTIGATION_MODEL_SIZE = var.failure_investigation_model_size
    }
  }
}

resource "aws_lambda_function_event_invoke_config" "failsafe_shutdown" {
  function_name                = aws_lambda_function.failsafe_shutdown.function_name
  maximum_event_age_in_seconds = 60
  maximum_retry_attempts       = 0
}

# Detect future silent failures of this lambda (e.g. import-time crash like the
# one observed after the multi-stage Dockerfile refactor, which left every ECS
# task failure undetected). Native CloudWatch → SNS, no extra code path to avoid
# adding new failure modes on the very component meant to be the last resort.
locals {
  failsafe_alerting_enabled = length(compact(var.failure_notification_receivers)) > 0 ? 1 : 0
}

# Non-blocking apply-time warning so an operator who left
# failure_notification_receivers empty knows the meta-alarm on the failsafe
# lambda itself is also off. The lambda still runs normally; the gap is
# specifically the lambda-crash case (see docs/deploying.md "Failsafe
# shutdown").
check "failsafe_alerting_configured" {
  assert {
    condition     = local.failsafe_alerting_enabled == 1
    error_message = "failure_notification_receivers is empty: no CloudWatch alarm on the failsafe_shutdown lambda's own Errors metric will be created. If the lambda ever crashes (e.g. packaging regression), task failures may leave Step Function executions blocked on waitForTaskToken indefinitely with no email alert — only the Slack integration (if configured in datalake_sdk) would surface it. Same opt-out trade-off as the pipeline-level failure emails being off."
  }
}

resource "aws_sns_topic" "failsafe_shutdown_lambda_failure" {
  count = local.failsafe_alerting_enabled
  name  = "${local.environment_name}_failsafe_shutdown_lambda_failure"
}

resource "aws_sns_topic_policy" "failsafe_shutdown_lambda_failure" {
  count  = local.failsafe_alerting_enabled
  arn    = aws_sns_topic.failsafe_shutdown_lambda_failure[0].arn
  policy = data.aws_iam_policy_document.failsafe_shutdown_lambda_failure_sns[0].json
}

data "aws_iam_policy_document" "failsafe_shutdown_lambda_failure_sns" {
  count = local.failsafe_alerting_enabled
  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.failsafe_shutdown_lambda_failure[0].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_subscription" "failsafe_shutdown_lambda_failure_email" {
  for_each  = local.failsafe_alerting_enabled == 1 ? toset(compact(var.failure_notification_receivers)) : toset([])
  topic_arn = aws_sns_topic.failsafe_shutdown_lambda_failure[0].arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "failsafe_shutdown_lambda_failure" {
  count               = local.failsafe_alerting_enabled
  alarm_name          = "${local.environment_name}_failsafe_shutdown_lambda_failure"
  alarm_description   = "Triggers when the ${aws_lambda_function.failsafe_shutdown.function_name} lambda errors. This lambda is the last-resort circuit breaker on task failures; any error here means task failures may go undetected."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    FunctionName = aws_lambda_function.failsafe_shutdown.function_name
  }
  alarm_actions = [aws_sns_topic.failsafe_shutdown_lambda_failure[0].arn]
}

resource "aws_iam_role" "lambda_failsafe_shutdown" {
  name = "${local.environment_name}_lambda_failsafe_shutdown"

  assume_role_policy = data.aws_iam_policy_document.lambda_failsafe_shutdown_assume.json
}

data "aws_iam_policy_document" "lambda_failsafe_shutdown_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "lambda_failsafe_shutdown" {
  name   = "${local.environment_name}_lambda_failsafe_shutdown"
  policy = data.aws_iam_policy_document.lambda_failsafe_shutdown.json
}

resource "aws_iam_policy_attachment" "lambda_failsafe_shutdown" {
  name       = "${local.environment_name}_lambda_failsafe_shutdown"
  roles      = [aws_iam_role.lambda_failsafe_shutdown.name]
  policy_arn = aws_iam_policy.lambda_failsafe_shutdown.arn
}

data "aws_iam_policy_document" "lambda_failsafe_shutdown" {
  statement {
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:List*",
      "bedrock:Get*",
      "bedrock:Describe*",
      "states:Describe*",
      "states:Get*",
      "states:List*",
      "logs:Get*",
      "logs:List*",
      "logs:Describe*",
      "ecr:Get*",
      "ecr:List*",
      "ecr:Describe*",
      "ec2:Get*",
      "ec2:List*",
      "ec2:Describe*",
      "ecs:Get*",
      "ecs:List*",
      "ecs:Describe*",
      "emr-serverless:Get*",
      "emr-serverless:List*",
      "emr-serverless:Describe*",
      "iam:Get*",
      "iam:List*",
      "iam:Describe*"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogGroupFields",
      "iam:PassRole",
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "states:DescribeExecution",
      "states:SendTaskFailure",
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.environment_name}*",
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}_slack_alerting_prod-*"
    ]
  }
}
