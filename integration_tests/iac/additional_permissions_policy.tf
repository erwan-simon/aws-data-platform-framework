# Sample additional IAM permissions used by the test_*_write tasks to verify additional_permissions plumbing. Replace with your real permissions, or delete if unused.
data "aws_iam_policy_document" "additional_permissions" {
  statement {
    actions = [
      "organizations:DescribeOrganization"
    ]
    resources = ["*"]
  }
}
