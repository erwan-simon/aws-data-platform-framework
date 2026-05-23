#!/usr/bin/env bash
# Invokes the failsafe_shutdown lambda with a synthetic ECS failure event
# (`dry_run: true`) and asserts the lambda runs to completion. Catches silent
# regressions like the post-multistage import crash that left task failures
# undetected for the lifetime of the broken image.
#
# Usage: failsafe_lambda_smoke_test.sh <project> <domain> <stage>
# Required env: AWS_DEFAULT_REGION (or AWS_REGION).
set -euo pipefail

PROJECT_NAME="${1:?project_name required}"
DOMAIN_NAME="${2:?domain_name required}"
STAGE_NAME="${3:?stage_name required}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="${REPO_ROOT}/scripts/fixtures/ecs_failure_event.json"
FUNCTION_NAME="${PROJECT_NAME}_${DOMAIN_NAME}_${STAGE_NAME}_failsafe_shutdown"
OUTPUT_FILE="$(mktemp -t failsafe_smoke_out_XXXXXX.json)"

echo "Invoking ${FUNCTION_NAME} with fixture ${FIXTURE}..."
INVOKE_OUT=$(aws lambda invoke \
    --function-name "${FUNCTION_NAME}" \
    --cli-binary-format raw-in-base64-out \
    --payload "file://${FIXTURE}" \
    "${OUTPUT_FILE}")

echo "Invoke metadata: ${INVOKE_OUT}"
echo "Lambda response:"
cat "${OUTPUT_FILE}"
echo

# aws lambda invoke exits 0 on transport success; the lambda itself may still
# have errored. Check both StatusCode == 200 and absence of FunctionError, then
# assert our dry_run sentinel.
if ! echo "${INVOKE_OUT}" | grep -q '"StatusCode": 200'; then
    echo "FAIL: lambda invocation returned non-200 status."
    exit 1
fi
if echo "${INVOKE_OUT}" | grep -q '"FunctionError"'; then
    echo "FAIL: lambda raised an unhandled error (FunctionError set)."
    exit 1
fi
if ! grep -q '"status": "dry_run_ok"' "${OUTPUT_FILE}"; then
    echo "FAIL: lambda response did not contain dry_run_ok marker."
    exit 1
fi

echo "OK: failsafe_shutdown lambda is responsive."
