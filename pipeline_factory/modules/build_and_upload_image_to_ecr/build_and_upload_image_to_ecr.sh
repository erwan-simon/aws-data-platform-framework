#!/bin/bash

base_image_uri=${1}
project_name=${2}
domain_name=${3}
stage_name=${4}
pipeline_name=${5}
task_name=${6}
task_input_tables=${7}
task_output_tables=${8}
is_sql_job=${9}
dockerfile_path=${10}
absolute_code_path=${11}
relative_code_path=${12}
aws_account_id=${13}
aws_region_name=${14}
ecr_name=${15}
target_image_tag=${16}
codeartifact_repository_endpoint=${17}
package_datalake_sdk=${18}
# if the terraform assumes a role, it should be here because this script execution does not benefit from terraform assume role
role_to_assume_arn=${19}

unique_id="job_${$}_${RANDOM}"
builder_name="datalake_builder_${unique_id}"

# Build context lives entirely under /tmp so the source tree stays clean and the
# cp never sees its own destination. Wiped on exit via trap (success or failure).
staging_dir=$(mktemp -d -t datalake_build_XXXXXX)
cleanup() {
  echo "🧹 Cleaning staging dir and Docker builder..."
  rm -rf "$staging_dir"
  docker buildx rm -f "$builder_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Dockerfile + sibling files (sandbox.ipynb, etc.) go at the build context root —
# the sandbox Dockerfiles reference `sandbox.ipynb` directly (no RELATIVE_CODE_PATH).
cp -rf "$dockerfile_path"/. "$staging_dir/" || { echo "Could not copy dockerfile context from $dockerfile_path"; exit 1; }

payload_dir="${staging_dir}/payload"
mkdir -p "$payload_dir"
cp -rf "$absolute_code_path"/. "$payload_dir/" || { echo "Could not copy task code from $absolute_code_path"; exit 1; }

# SQL tasks don't need a requirements.txt — the SDK is already in the base image.
# Stub an empty one so the Dockerfile's COPY + pip install stay a no-op without branching.
[ -f "${payload_dir}/requirements.txt" ] || touch "${payload_dir}/requirements.txt"

if [ "$package_datalake_sdk" = "true" ];
then
    datalake_sdk_path="$(cd "$(dirname "$0")/../../../datalake_sdk" && pwd)"
    rm -rf "${datalake_sdk_path}/.venv" "${datalake_sdk_path}/.mypy_cache/"
    cp -rf "${datalake_sdk_path}" "${payload_dir}/" || { echo "Could not copy datalake_sdk from ${datalake_sdk_path}"; exit 1; }
fi

cd "$staging_dir"

if [ ! -z "$role_to_assume_arn" ]
then
    export OLD_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export OLD_SECRET_ACCESS_ID=$AWS_SECRET_ACCESS_KEY
    export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $(aws sts assume-role --role-arn ${role_to_assume_arn} --role-session-name GitlabRunnerSession --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" --output text))
fi

if ! aws ecr get-login-password --region $aws_region_name | docker login -u AWS ${aws_account_id}.dkr.ecr.${aws_region_name}.amazonaws.com --password-stdin 2> "${staging_dir}/login_error_message.txt";
then
  if grep -q "The specified item already exists in the keychain." "${staging_dir}/login_error_message.txt"
  then
    # https://github.com/hashicorp/terraform-provider-helm/issues/989
    echo "Cannot login to ECR due to bug, trying to build and push image anyway"
  else
    cat "${staging_dir}/login_error_message.txt"
    echo "Cannot login to ECR for unmanaged reason ('$(cat "${staging_dir}/login_error_message.txt")'), Exiting..."
    exit 1;
  fi
fi

# Dedicated tag holding the BuildKit cache manifest for this ECR repo. Separate
# from the runtime image tag so (a) `mode=max` can export every stage (including
# heavy builder stages like the EMR Python source build) and (b) pulling the
# cache doesn't drag in the full runtime image. Same tag every build — the ECR
# repo is MUTABLE and its lifecycle policy keeps enough images to retain it.
cache_image_ref=${aws_account_id}.dkr.ecr.${aws_region_name}.amazonaws.com/${ecr_name}:buildcache
echo "Using BuildKit cache => ${cache_image_ref}"
codeartifact_repository_token=$(aws codeartifact get-authorization-token --domain ${project_name} --domain-owner ${aws_account_id} --region ${aws_region_name} --query authorizationToken --output text)
if [ ! $codeartifact_repository_token ]
then
    echo "Could not get codeartifact_repository_token from codeartifact domain ${project_name} with owner ${aws_account_id} and region ${aws_region_name}"
    exit 1;
fi

unique_id="job_${$}_${RANDOM}"
builder_name="datalake_builder_${unique_id}"

# `--cache-to type=registry` requires the docker-container (or kubernetes)
# buildx driver — the default `docker` driver (what plain docker / docker:dind
# ships with) doesn't support registry cache export. Create + select a named
# builder idempotently so the cost is paid once per runner.
echo "Creating ephemeral builder: $builder_name"
docker buildx create --name "$builder_name" --driver docker-container --use

if ! DOCKER_BUILDKIT=1 \
    CODEARTIFACT_REPOSITORY_TOKEN=${codeartifact_repository_token} \
  docker buildx build "$staging_dir" \
  -f "${dockerfile_path}/Dockerfile" \
  -t ${aws_account_id}.dkr.ecr.${aws_region_name}.amazonaws.com/${ecr_name}:${target_image_tag} \
  --build-arg BASE_IMAGE_URI=${base_image_uri} \
  --build-arg RELATIVE_CODE_PATH=./payload \
  --build-arg PROJECT_NAME=${project_name} \
  --build-arg DOMAIN_NAME=${domain_name} \
  --build-arg STAGE_NAME=${stage_name} \
  --build-arg PIPELINE_NAME=${pipeline_name} \
  --build-arg TASK_NAME=${task_name} \
  --build-arg INPUT_TABLES="${task_input_tables}" \
  --build-arg OUTPUT_TABLES="${task_output_tables}" \
  --build-arg IS_SQL_JOB=${is_sql_job} \
  --build-arg AWS_REGION=${aws_region_name} \
  --build-arg CODEARTIFACT_REPOSITORY_ENDPOINT=${codeartifact_repository_endpoint} \
  --secret id=CODEARTIFACT_REPOSITORY_TOKEN \
  --cache-from type=registry,ref=${cache_image_ref} \
  --cache-to type=registry,ref=${cache_image_ref},mode=max,image-manifest=true,oci-mediatypes=true \
  --provenance=false \
  --push;  # https://stackoverflow.com/questions/65608802/cant-deploy-container-image-to-lambda-function
then
  echo "Cannot build and push docker image"
  exit 1
fi
