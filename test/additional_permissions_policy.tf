data "aws_iam_policy_document" "additional_permissions" {
  statement {
    actions = [
      "organizations:DescribeOrganization"
    ]
    resources = ["*"]
  }
}
