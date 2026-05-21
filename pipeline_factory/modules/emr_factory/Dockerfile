# syntax=docker/dockerfile:1
ARG BASE_IMAGE_URI
FROM --platform=linux/amd64 ${BASE_IMAGE_URI}

# https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/application-custom-image.html

USER root
# MODIFICATIONS GO HERE

ARG RELATIVE_CODE_PATH
WORKDIR /usr/app/src
COPY ${RELATIVE_CODE_PATH}/requirements.txt .
ARG CODEARTIFACT_REPOSITORY_ENDPOINT
RUN --mount=type=secret,id=CODEARTIFACT_REPOSITORY_TOKEN,env=CODEARTIFACT_REPOSITORY_TOKEN \
    pip install \
    --index-url="https://aws:${CODEARTIFACT_REPOSITORY_TOKEN}@${CODEARTIFACT_REPOSITORY_ENDPOINT}" \
    --extra-index-url="https://pypi.python.org/simple/" \
    -r requirements.txt --no-cache-dir
COPY ${RELATIVE_CODE_PATH}/code/. /usr/app/src/task_code/
RUN chown -R hadoop:hadoop /usr/app/src/

ARG PROJECT_NAME \
	DOMAIN_NAME \
	STAGE_NAME \
	IS_SQL_JOB \
	PIPELINE_NAME \
	TASK_NAME \
	INPUT_TABLES \
	OUTPUT_TABLES \
	AWS_REGION
# AWS_REGION is set first so the next ENV can safely derive AWS_DEFAULT_REGION from it (hadolint DL3044).
ENV AWS_REGION=${AWS_REGION}
ENV PROJECT_NAME=${PROJECT_NAME} \
	DOMAIN_NAME=${DOMAIN_NAME} \
	STAGE_NAME=${STAGE_NAME} \
	IS_SQL_JOB=${IS_SQL_JOB} \
	PIPELINE_NAME=${PIPELINE_NAME} \
	TASK_NAME=${TASK_NAME} \
	INPUT_TABLES=${INPUT_TABLES} \
	OUTPUT_TABLES=${OUTPUT_TABLES} \
	AWS_DEFAULT_REGION=${AWS_REGION}

# end of modifications
# EMRS will run the image as hadoop

USER hadoop:hadoop
