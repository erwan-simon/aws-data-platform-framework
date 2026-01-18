resource "aws_lakeformation_resource" "register_data_bucket_location" {
  arn                   = aws_s3_bucket.data.arn
  role_arn              = aws_iam_role.give_access_to_lakeformation_to_data_bucket.arn
  hybrid_access_enabled = false
}

locals {
  # shorten role name to comply with AWS resources name length limit
  give_access_to_lakeformation_to_data_bucket_role_name           = "${local.environment_name}_give_access_to_lakeformation_to_data_bucket"
  shortened_give_access_to_lakeformation_to_data_bucket_role_name = length(local.give_access_to_lakeformation_to_data_bucket_role_name) > 64 ? "${substr(local.give_access_to_lakeformation_to_data_bucket_role_name, 0, 54)}_${substr(sha1(local.give_access_to_lakeformation_to_data_bucket_role_name), 0, 9)}" : local.give_access_to_lakeformation_to_data_bucket_role_name
}

resource "aws_iam_role" "give_access_to_lakeformation_to_data_bucket" {
  name = local.shortened_give_access_to_lakeformation_to_data_bucket_role_name

  assume_role_policy = data.aws_iam_policy_document.give_access_to_lakeformation_to_data_bucket_assume.json
  tags = {
    Name = local.give_access_to_lakeformation_to_data_bucket_role_name
  }
}

data "aws_iam_policy_document" "give_access_to_lakeformation_to_data_bucket_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = ["lakeformation.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "give_access_to_lakeformation_to_data_bucket" {
  name   = local.shortened_give_access_to_lakeformation_to_data_bucket_role_name
  policy = data.aws_iam_policy_document.give_access_to_lakeformation_to_data_bucket.json
  tags = {
    Name = local.give_access_to_lakeformation_to_data_bucket_role_name
  }
}

resource "aws_iam_policy_attachment" "give_access_to_lakeformation_to_data_bucket" {
  name       = local.shortened_give_access_to_lakeformation_to_data_bucket_role_name
  roles      = [aws_iam_role.give_access_to_lakeformation_to_data_bucket.name]
  policy_arn = aws_iam_policy.give_access_to_lakeformation_to_data_bucket.arn
}

data "aws_iam_policy_document" "give_access_to_lakeformation_to_data_bucket" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }
  statement {
    actions = [
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [
      aws_s3_bucket.data.arn
    ]
  }
  statement {
    actions = [
      "s3:ListAllMyBuckets"
    ]
    resources = [
      "*"
    ]
  }
}
