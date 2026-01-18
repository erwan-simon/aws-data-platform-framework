resource "aws_iam_policy" "permissions_required_for_consumption" {
  name   = "${local.environment_name}_permissions_required_for_consumption"
  policy = data.aws_iam_policy_document.permissions_required_for_consumption.json
}

data "aws_iam_policy_document" "permissions_required_for_consumption" {
  statement {
    actions = [
      "glue:GetDatabases",
      "glue:GetDatabase",
      "glue:GetTables",
      "glue:GetTable",
      "glue:GetPartitions",
      "glue:GetPartition"
    ]
    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/${var.project_name}_${var.domain_name}_${var.stage_name}_*", # Change here if you do not want to give access to your whole datalake
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}_${var.domain_name}_${var.stage_name}_*/*"   # Change here if you do not want to give access to your whole datalake
    ]
  }
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject"
    ]
    resources = [
      "${aws_s3_bucket.data.arn}",
      "${aws_s3_bucket.data.arn}/*" # Change here if you do not want to give access to your whole datalake
    ]
  }
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:GetBucketLocation"
    ]
    resources = [
      "${aws_s3_bucket.technical.arn}",
      "${aws_s3_bucket.technical.arn}/*"
    ]
  }
  statement {
    actions = [
      "athena:GetWorkgroup",
      "athena:GetQueryResults",
      "athena:GetQueryExecutions",
      "athena:GetQueryExecution",
      "athena:ListQueryExecutions",
      "athena:CancelQueryExecution",
      "athena:RunQuery",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution"
    ]
    resources = [
      "${aws_athena_workgroup.main.arn}"
    ]
  }
  statement {
    actions = [
      "athena:ListWorkGroups"
    ]
    resources = ["*"]
  }
}
