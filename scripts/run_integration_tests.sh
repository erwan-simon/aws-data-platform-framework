#!/usr/bin/env bash
# Deploys one integration-test target and runs its state machine end-to-end.
#
# Usage: run_integration_tests.sh <iac_dir> <domain_name> <pipeline_name>
# Example:
#   scripts/run_integration_tests.sh integration_tests/iac datalake_test tests
#   scripts/run_integration_tests.sh _integration_test/datalake_scaffold/iac datalake_scaffold main
#
# Required env vars: ACCOUNT_ID, AWS_DEFAULT_REGION, PROJECT_NAME, STAGE_NAME,
#                    TERRAFORM_BACKEND_BUCKET, TERRAFORM_BACKEND_DYNAMODB
set -euo pipefail

IAC_DIR="${1:?iac_dir required}"
DOMAIN_NAME="${2:?domain_name required}"
PIPELINE_NAME="${3:?pipeline_name required}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "${REPO_ROOT}/${IAC_DIR}"

deploy_start=$(date +%s)
terraform init \
    -backend-config="bucket=${TERRAFORM_BACKEND_BUCKET}" \
    -backend-config="dynamodb_table=${TERRAFORM_BACKEND_DYNAMODB}"
terraform workspace new "${STAGE_NAME}" || terraform workspace select "${STAGE_NAME}"
terraform apply --auto-approve
deploy_end=$(date +%s)
deploy_duration=$((deploy_end - deploy_start))
printf 'Deployment duration for %s/%s: %dm%02ds (%ds total)\n' \
    "${DOMAIN_NAME}" "${PIPELINE_NAME}" \
    $((deploy_duration / 60)) $((deploy_duration % 60)) "${deploy_duration}"

state_machine_arn="arn:aws:states:${AWS_DEFAULT_REGION}:${ACCOUNT_ID}:stateMachine:${PROJECT_NAME}_${DOMAIN_NAME}_${STAGE_NAME}_${PIPELINE_NAME}"
python "${REPO_ROOT}/scripts/run_integration_tests.py" "${state_machine_arn}"
