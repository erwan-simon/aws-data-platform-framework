# Grants DROP to the check_and_clean task so it can wipe domain tables at the end of the integration test. Delete if you remove check_and_clean.
resource "aws_lakeformation_permissions" "allow_check_and_clean_to_delete_the_tables" {
  principal   = module.pipeline.pipeline_tasks["check_and_clean"]["iam_role_arn"]
  permissions = ["DROP"]

  table {
    database_name = module.domain.domain_glue_database_name
    wildcard      = true
  }
}
