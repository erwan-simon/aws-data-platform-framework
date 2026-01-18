resource "aws_bedrock_inference_profile" "large" {
  name        = "${local.environment_name}_large"
  description = "Bedrock inference profile for ${local.environment_name} using a large LLM"

  model_source {
    copy_from = "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
  }
}

resource "aws_bedrock_inference_profile" "medium" {
  name        = "${local.environment_name}_medium"
  description = "Bedrock inference profile for ${local.environment_name} using a medium LLM"

  model_source {
    copy_from = "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:inference-profile/eu.anthropic.claude-3-haiku-20240307-v1:0"
  }
}

resource "aws_bedrock_inference_profile" "small" {
  name        = "${local.environment_name}_small"
  description = "Bedrock inference profile for ${local.environment_name} using a small LLM"

  model_source {
    copy_from = "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:inference-profile/eu.amazon.nova-pro-v1:0"
  }
}
