# syntax=docker/dockerfile:1

# python:3.11-slim ships no toolchain, but numpy 1.26.x has cp311 manylinux2014
# wheels — no source build needed, so a single stage is enough.
# hadolint ignore=DL3029
FROM --platform=linux/amd64 python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends awscli curl && rm -rf /var/lib/apt/lists/* && \
	pip3 install --no-cache-dir jupyter notebook poetry==2.1.4 papermill

WORKDIR /usr/app/src
ARG RELATIVE_CODE_PATH
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/pyproject.toml .
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/. .
RUN poetry config virtualenvs.create false --local && poetry install
COPY ${RELATIVE_CODE_PATH}/requirements.txt .
RUN pip install -r requirements.txt --no-cache-dir

WORKDIR /usr/app/src
COPY sandbox.ipynb .
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
	AWS_REGION \
    TASK_ADDITIONAL_PARAMETERS
ENV PROJECT_NAME=${PROJECT_NAME} \
	DOMAIN_NAME=${DOMAIN_NAME} \
	STAGE_NAME=${STAGE_NAME} \
	IS_SQL_JOB=${IS_SQL_JOB} \
	PIPELINE_NAME=${PIPELINE_NAME} \
	TASK_NAME=${TASK_NAME} \
	INPUT_TABLES=${INPUT_TABLES} \
	OUTPUT_TABLES=${OUTPUT_TABLES} \
	AWS_DEFAULT_REGION=${AWS_REGION} \
	AWS_REGION=${AWS_REGION} \
    TASK_ADDITIONAL_PARAMETERS=${TASK_ADDITIONAL_PARAMETERS} \
    PYTHONUNBUFFERED=1
