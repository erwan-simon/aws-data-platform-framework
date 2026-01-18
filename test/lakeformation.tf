resource "aws_lakeformation_permissions" "allow_check_and_clean_to_delete_the_tables" {
  principal   = module.integration_tests_pipeline.pipeline_tasks["check_and_clean"]["iam_role_arn"]
  permissions = ["DROP"]

  table {
    database_name = module.domain.domain_glue_database_name
    wildcard      = true
  }
}
