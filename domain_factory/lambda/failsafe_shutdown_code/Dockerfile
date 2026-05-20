# syntax=docker/dockerfile:1

# ---- Builder stage ----
# numpy 1.26.x (pinned by datalake_sdk to keep pyspark.pandas working on
# EMR Serverless) ships no Python 3.13 wheel and falls back to a source build
# via meson. We need a C/C++ toolchain to compile it, but we don't want to
# ship gcc/g++/make in the final lambda image (≈150 MB of dead weight). So we
# build deps in a stage that has the toolchain and copy only the resolved
# site-packages into the runtime stage.
FROM --platform=linux/amd64 public.ecr.aws/lambda/python:3.13 AS builder
RUN dnf install -y gcc gcc-c++ make && dnf clean all
RUN pip3 install --no-cache-dir poetry==2.1.4
ARG RELATIVE_CODE_PATH
WORKDIR /build
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/pyproject.toml .
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/. .
RUN poetry config virtualenvs.create false --local && poetry install --extras agent
COPY ${RELATIVE_CODE_PATH}/requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt --no-cache-dir

# ---- Runtime stage ----
# Same base image as builder so compiled extensions stay ABI-compatible.
FROM --platform=linux/amd64 public.ecr.aws/lambda/python:3.13
COPY --from=builder /var/lang/lib/python3.13/site-packages /var/lang/lib/python3.13/site-packages
COPY --from=builder /var/lang/bin /var/lang/bin
WORKDIR $LAMBDA_TASK_ROOT/
CMD [ "task_code.main.main" ]
ARG RELATIVE_CODE_PATH
COPY ${RELATIVE_CODE_PATH}/code/. ./task_code/
ENV PYTHONPATH /usr/app/src/task_code/

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
    TASK_ADDITIONAL_PARAMETERS=${TASK_ADDITIONAL_PARAMETERS}
