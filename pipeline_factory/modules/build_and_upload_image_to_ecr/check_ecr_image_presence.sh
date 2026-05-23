#!/bin/bash
# Wrapper for terraform's `data "external"`: checks whether a specific image tag
# exists in an ECR repository, surfacing the result as JSON so it can feed
# `triggers_replace` of the image build resource.
#
# Contract with terraform external provider:
# - Query is read from stdin as a JSON object with string-only values.
# - Output MUST be a JSON object with string-only values on stdout, exit 0.
# - A non-zero exit is treated as a hard plan error — never propagate the
#   underlying `aws ecr describe-images` exit code (it returns non-zero on
#   ImageNotFoundException, which is normal data in our case, not an error).

set -euo pipefail

query=$(cat)
repository_name=$(echo "${query}" | jq -r .repository_name)
image_tag=$(echo "${query}" | jq -r .image_tag)
region=$(echo "${query}" | jq -r .region)
role_to_assume=$(echo "${query}" | jq -r .role_to_assume)

# Mirror build_and_upload_image_to_ecr.sh: assume the role if one was passed,
# since the script runs outside terraform's provider-level assume_role.
if [ -n "${role_to_assume}" ] && [ "${role_to_assume}" != "null" ]; then
    eval "$(aws sts assume-role \
        --role-arn "${role_to_assume}" \
        --role-session-name "tf-external-ecr-check" \
        --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
        --output text \
        | awk '{print "export AWS_ACCESS_KEY_ID=" $1 "; export AWS_SECRET_ACCESS_KEY=" $2 "; export AWS_SESSION_TOKEN=" $3}')"
fi

if aws ecr describe-images \
        --repository-name "${repository_name}" \
        --image-ids imageTag="${image_tag}" \
        --region "${region}" >/dev/null 2>&1; then
    printf '{"present_tag":"%s"}' "${image_tag}"
else
    # Tag isn't in ECR — could be a brand-new repo (no images yet), a tag that
    # was expired by lifecycle, or any other reason. In all cases terraform
    # should treat this as "rebuild needed", which is what the MISSING signal
    # in triggers_replace achieves.
    printf '{"present_tag":"MISSING"}'
fi
exit 0
