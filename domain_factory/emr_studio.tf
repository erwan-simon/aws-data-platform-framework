resource "aws_emr_studio" "main" {
  auth_mode                   = "IAM"
  default_s3_location         = "s3://${aws_s3_bucket.technical.bucket}/emr_studio/"
  engine_security_group_id    = aws_security_group.main.id
  name                        = local.environment_name
  service_role                = aws_iam_role.emr_studio.arn
  subnet_ids                  = data.aws_subnets.main.ids
  vpc_id                      = data.aws_vpc.main.id
  workspace_security_group_id = aws_security_group.main.id
  depends_on                  = [aws_iam_policy_attachment.emr_studio]
}

resource "aws_iam_role" "emr_studio" {
  name = "${local.environment_name}_emr_studio"

  assume_role_policy = data.aws_iam_policy_document.emr_studio_assume.json
}

data "aws_iam_policy_document" "emr_studio_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = ["elasticmapreduce.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "emr_studio" {
  name   = "${local.environment_name}_emr_studio"
  policy = data.aws_iam_policy_document.emr_studio.json
}

resource "aws_iam_policy_attachment" "emr_studio" {
  name       = "${local.environment_name}_emr_studio"
  roles      = [aws_iam_role.emr_studio.name]
  policy_arn = aws_iam_policy.emr_studio.arn
}

data "aws_iam_policy_document" "emr_studio" {
  statement {
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CancelSpotInstanceRequests",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateNetworkInterface",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteNetworkInterface",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteTags",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstances",
      "ec2:DescribeKeyPairs",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeNetworkAcls",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribePrefixLists",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotInstanceRequests",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcEndpointServices",
      "ec2:DescribeVpcs",
      "ec2:DetachNetworkInterface",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:RequestSpotInstances",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:DeleteVolume",
      "ec2:DescribeVolumeStatus",
      "ec2:DescribeVolumes",
      "ec2:DetachVolume",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListInstanceProfiles",
      "iam:ListRolePolicies",
      "iam:PassRole",
      "sdb:BatchPutAttributes",
      "sdb:Select",
      "sqs:CreateQueue",
      "sqs:Delete*",
      "sqs:GetQueue*",
      "sqs:PurgeQueue",
      "sqs:ReceiveMessage",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DeleteAlarms",
      "application-autoscaling:RegisterScalableTarget",
      "application-autoscaling:DeregisterScalableTarget",
      "application-autoscaling:PutScalingPolicy",
      "application-autoscaling:DeleteScalingPolicy",
      "application-autoscaling:Describe*",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:DescribeImages"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "s3:GetEncryptionConfiguration",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject*",
      "s3:DeleteObject"
    ]
    resources = [
      aws_s3_bucket.technical.arn,
      "${aws_s3_bucket.technical.arn}/emr_studio/*",
      "${aws_s3_bucket.technical.arn}/emr/*",
    ]
  }
  statement {
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot*"]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values   = ["spot.amazonaws.com"]
    }
  }
}
