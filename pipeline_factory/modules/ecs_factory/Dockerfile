# syntax=docker/dockerfile:1
ARG BASE_IMAGE_URI
# hadolint ignore=DL3029
FROM --platform=linux/amd64 ${BASE_IMAGE_URI}

ARG RELATIVE_CODE_PATH
COPY ${RELATIVE_CODE_PATH}/requirements.txt .
ARG CODEARTIFACT_REPOSITORY_ENDPOINT
RUN --mount=type=secret,id=CODEARTIFACT_REPOSITORY_TOKEN,env=CODEARTIFACT_REPOSITORY_TOKEN \
    pip install \
    --index-url="https://aws:${CODEARTIFACT_REPOSITORY_TOKEN}@${CODEARTIFACT_REPOSITORY_ENDPOINT}" \
    --extra-index-url="https://pypi.python.org/simple/" \
    -r requirements.txt --no-cache-dir
COPY ${RELATIVE_CODE_PATH}/code/. /usr/app/src/task_code/
ENV PYTHONPATH /usr/app/src/task_code/
CMD [ "python", "-m", "datalake_sdk.native_python_processing_wrapper"]

ARG PROJECT_NAME \
	DOMAIN_NAME \
	STAGE_NAME \
	IS_SQL_JOB \
	PIPELINE_NAME \
	TASK_NAME \
	INPUT_TABLES \
	OUTPUT_TABLES \
	AWS_REGION
ENV PROJECT_NAME=${PROJECT_NAME} \
	DOMAIN_NAME=${DOMAIN_NAME} \
	STAGE_NAME=${STAGE_NAME} \
	IS_SQL_JOB=${IS_SQL_JOB} \
	PIPELINE_NAME=${PIPELINE_NAME} \
	TASK_NAME=${TASK_NAME} \
	INPUT_TABLES=${INPUT_TABLES} \
	OUTPUT_TABLES=${OUTPUT_TABLES} \
	AWS_DEFAULT_REGION=${AWS_REGION} \
	AWS_REGION=${AWS_REGION}
