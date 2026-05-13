#!/usr/bin/env bash
# Generates a minimal domain from the cookiecutter template at `_integration_test/datalake_scaffold/`.
# Used as one of the two integration test targets (the other being the in-tree `integration_tests/`).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/_integration_test"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

git_remote_raw=$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || echo "")
git_repository=$(printf '%s' "$git_remote_raw" | sed -E 's#://[^/@]+@#://#')

cookiecutter "${REPO_ROOT}/cookiecutter_template" \
    --no-input \
    --output-dir "${OUTPUT_DIR}" \
    project_name=poc \
    domain_name=datalake_scaffold \
    pipeline_name=main \
    aws_account_id="${ACCOUNT_ID:?ACCOUNT_ID must be set}" \
    aws_region="${AWS_DEFAULT_REGION:-eu-west-1}" \
    terraform_backend_bucket_name="${TERRAFORM_BACKEND_BUCKET:?TERRAFORM_BACKEND_BUCKET must be set}" \
    terraform_backend_dynamodb_name="${TERRAFORM_BACKEND_DYNAMODB:?TERRAFORM_BACKEND_DYNAMODB must be set}" \
    failure_notification_receivers="erwan.simon+datalake_tests@revolve.team" \
    datalake_admin_principal_arns="AWSReservedSSO_AdministratorAccess_b46bf0a32c9dd401,federated-access,poc_devops_platform_ci_access_prod_gitlab_oidc_access,datazone_usr_role_3vtoy9hfgod2xi_d9p4135fusi7py" \
    git_repository="${git_repository}" \
    skip_emr_serverless_sandbox_creation=true \
    domain_factory_source="../../../domain_factory" \
    pipeline_factory_source="../../../pipeline_factory"

echo "Generated at ${OUTPUT_DIR}/datalake_scaffold/iac"
