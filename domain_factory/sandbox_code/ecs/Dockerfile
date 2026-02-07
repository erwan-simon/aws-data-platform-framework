# syntax=docker/dockerfile:1
# hadolint ignore=DL3029
FROM --platform=linux/amd64 python:3.13

RUN pip3 install --no-cache-dir jupyter notebook poetry==2.1.4
WORKDIR /usr/app/src
COPY sandbox.ipynb .
ARG RELATIVE_CODE_PATH
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/pyproject.toml .
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/. .
RUN poetry config virtualenvs.create false --local && poetry install
COPY ${RELATIVE_CODE_PATH}/requirements.txt .
RUN pip install -r requirements.txt --no-cache-dir
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
