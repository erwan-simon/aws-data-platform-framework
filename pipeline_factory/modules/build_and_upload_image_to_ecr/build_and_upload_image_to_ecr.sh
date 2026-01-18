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

cd ${dockerfile_path}
rm -rf temp_build/${relative_code_path}
mkdir -p temp_build/${relative_code_path}
cp -rf $absolute_code_path/* temp_build/${relative_code_path} || (echo "Could not copy task code from $absolute_code_path/*" && exit 1)

if [ "$package_datalake_sdk" = "true" ];
then
    datalake_sdk_path="../../../datalake_sdk"
    rm -rf "${datalake_sdk_path}/.venv" "${datalake_sdk_path}/.mypy_cache/"
    cp -rf "${datalake_sdk_path}" "temp_build/${relative_code_path}" || (echo "Could not copy datalake_sdk sdk code from ${datalake_sdk_path}" && exit 1)

    if ! cd temp_build/${relative_code_path}/datalake_sdk;
    then
      echo "Did not find temp_build/${relative_code_path}/datalake_sdk directory"
      exit 1
    fi
    cd -
fi

if [ ! -z "$role_to_assume_arn" ]
then
    export OLD_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export OLD_SECRET_ACCESS_ID=$AWS_SECRET_ACCESS_KEY
    export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $(aws sts assume-role --role-arn ${role_to_assume_arn} --role-session-name GitlabRunnerSession --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" --output text))
fi

if ! aws ecr get-login-password --region $aws_region_name | docker login -u AWS ${aws_account_id}.dkr.ecr.${aws_region_name}.amazonaws.com --password-stdin 2> temp_build/${relative_code_path}/login_error_message.txt;
then
  if grep -q "The specified item already exists in the keychain." temp_build/${relative_code_path}/login_error_message.txt
  then
    # https://github.com/hashicorp/terraform-provider-helm/issues/989
    echo "Cannot login to ECR due to bug, trying to build and push image anyway"
  else
    cat temp_build/${relative_code_path}/login_error_message.txt
    echo "Cannot login to ECR for unmanaged reason ('$(cat temp_build/${relative_code_path}/login_error_message.txt)'), Exiting..."
    exit 1;
  fi
fi

# Get latest tag from image repository for this environment in ECR in order to maximize cache usage during docker build
latest_image_tag=$(aws ecr describe-images --repository-name ${ecr_name} --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' | tr -d '"')
echo "Using following image as cache => ${ecr_name}:${latest_image_tag}"
codeartifact_repository_token=$(aws codeartifact get-authorization-token --domain ${project_name} --domain-owner ${aws_account_id} --region ${aws_region_name} --query authorizationToken --output text)
if [ ! $codeartifact_repository_token ]
then
    echo "Could not get codeartifact_repository_token from codeartifact domain ${project_name} with owner ${aws_account_id} and region ${aws_region_name}"
    exit 1;
fi

if ! DOCKER_BUILDKIT=1 \
    CODEARTIFACT_REPOSITORY_TOKEN=${codeartifact_repository_token} \
  docker buildx build . \
  -t ${aws_account_id}.dkr.ecr.${aws_region_name}.amazonaws.com/${ecr_name}:${target_image_tag} \
  --build-arg BASE_IMAGE_URI=${base_image_uri} \
  --build-arg RELATIVE_CODE_PATH=./temp_build/${relative_code_path} \
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
  --cache-from type=registry,ref=${aws_account_id}.dkr.ecr.${aws_region_name}.amazonaws.com/${ecr_name}:${latest_image_tag} \
  --cache-to type=inline \
  --provenance=false;  # https://stackoverflow.com/questions/65608802/cant-deploy-container-image-to-lambda-function
then
  echo "Cannot build docker image"
  exit 1
fi

if ! docker push ${aws_account_id}.dkr.ecr.${aws_region_name}.amazonaws.com/${ecr_name}:${target_image_tag};
then
  echo "Cannot push built docker image to ECR"
  exit 1
fi

rm -rf temp_build/${relative_code_path}
