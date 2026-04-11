resource "aws_iam_role" "ecs_task" {
  name = "${local.environment_name}_${var.pipeline_name}_${var.task_name}"

  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags = {
    "${var.domain_object.project_name}:jupyter_sandbox" = "allowed"
  }
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "ecs_task" {
  name   = "${local.environment_name}_${var.pipeline_name}_${var.task_name}"
  policy = data.aws_iam_policy_document.ecs_task.json
}

resource "aws_iam_role_policy_attachment" "ecs_task" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task.arn
}

data "aws_iam_policy_document" "dummy" {
  # creating a dummy aws_iam_policy_document to make that the coalesce takes something if there is no additional_permissions
  # harmless way of making it works if you ask me
  statement {
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::${var.domain_object.technical_bucket_name}",
    ]
  }
}


data "aws_iam_policy_document" "ecs_task" {
  source_policy_documents = [
    coalesce(var.task_configuration["additional_permissions"],
    data.aws_iam_policy_document.dummy.json)
  ]
  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      "arn:aws:s3:::${var.domain_object.technical_bucket_name}",
      "arn:aws:s3:::${var.domain_object.datalake_bucket_name}",
      "arn:aws:s3:::${var.domain_object.technical_bucket_name}/${var.pipeline_name}/${var.task_name}/*",
      "arn:aws:s3:::${var.domain_object.technical_bucket_name}/*",
      "arn:aws:s3:::${var.domain_object.datalake_bucket_name}/*",
    ]
  }
  statement {
    actions = [
      "glue:SearchTables",
      "glue:BatchCreatePartition",
      "glue:CreateRegistry",
      "glue:ListSchemaVersions",
      "glue:CreatePartitionIndex",
      "glue:DeleteDatabase",
      "glue:RemoveSchemaVersionMetadata",
      "glue:GetTableVersions",
      "glue:GetPartitions",
      "glue:BatchDeletePartition",
      "glue:DeleteTableVersion",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:GetSchema",
      "glue:DeleteRegistry",
      "glue:DeleteSchema",
      "glue:DeletePartitionIndex",
      "glue:GetTableVersion",
      "glue:UpdateRegistry",
      "glue:ListSchemas",
      "glue:CreatePartition",
      "glue:UntagResource",
      "glue:PutResourcePolicy",
      "glue:UpdatePartition",
      "glue:TagResource",
      "glue:GetSchemaByDefinition",
      "glue:RegisterSchemaVersion",
      "glue:UpdateDatabase",
      "glue:CreateTable",
      "glue:BatchUpdatePartition",
      "glue:DeleteResourcePolicy",
      "glue:GetTables",
      "glue:GetSchemaVersionsDiff",
      "glue:UpdateSchema",
      "glue:GetDatabases",
      "glue:GetPartitionIndexes",
      "glue:GetTable",
      "glue:GetDatabase",
      "glue:PutSchemaVersionMetadata",
      "glue:GetPartition",
      "glue:GetSchemaVersion",
      "glue:CreateDatabase",
      "glue:BatchDeleteTableVersion",
      "glue:CreateSchema",
      "glue:BatchDeleteTable",
      "glue:DeleteSchemaVersions",
      "glue:DeletePartition"
    ]
    resources = [
      "arn:aws:glue:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:table/*/*",
      "arn:aws:glue:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:schema/*",
      "arn:aws:glue:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:database/*",
      "arn:aws:glue:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:registry/*",
      "arn:aws:glue:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:userDefinedFunction/*/*",
      "arn:aws:glue:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:catalog",
      "arn:aws:glue:${var.domain_object.aws_region}:${var.domain_object.aws_caller_identity_account_id}:database/default",
    ]
  }
  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::${var.domain_object.technical_bucket_name}/${var.pipeline_name}/${var.task_name}/logs/*",
      "arn:aws:s3:::${var.domain_object.technical_bucket_name}/*",
      "arn:aws:s3:::${var.domain_object.datalake_bucket_name}/*",
    ]
  }
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogGroupFields",
      "glue:UpdateClassifier",
      "lakeformation:UpdateResource",
      "lakeformation:GetDataAccess",
      "lakeformation:GetDataLakeSettings",
      "lakeformation:RegisterResource",
      "lakeformation:UpdateLFTag",
      "lakeformation:UpdateTableObjects",
      "lakeformation:AddLFTagsToResource",
      "lakeformation:RemoveLFTagsFromResource",
      "organizations:DescribeOrganization",
      "ram:CreateResourceShare",
      "ram:GetResourceShares",
      "ram:ListResourceSharePermissions",
      "ram:AssociateResourceShare",
      "states:SendTask*",
      "ecr:GetAuthorizationToken",
      "athena:*",
      "states:DescribeExecution"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:DescribeRegistry",
      "ecr:DescribeImages",
      "ecr:GetRepositoryPolicy",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = [module.image_build_and_upload.ecr_arn]
  }
}
