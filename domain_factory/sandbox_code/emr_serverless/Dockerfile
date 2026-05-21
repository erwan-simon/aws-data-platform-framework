# syntax=docker/dockerfile:1
# https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/application-custom-image.html

# EMR 7.1.0 ships Python 3.11 in its base image (release notes:
# https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-release-app-versions-7.x.html).
# We use it directly — no source build, no toolchain — and pip-install poetry
# + the SDK on top.
FROM --platform=linux/amd64 public.ecr.aws/emr-serverless/spark/emr-7.1.0:20240823
USER root

# Sandbox image: jupyter/notebook left unpinned (dev tools, poetry is the only pinned dep).
# hadolint ignore=DL3013
RUN python3.11 -m ensurepip --upgrade && \
	python3.11 -m pip install --no-cache-dir poetry==2.1.4 jupyter notebook

WORKDIR /usr/app/src
ARG RELATIVE_CODE_PATH
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/pyproject.toml .
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/. .
RUN poetry config virtualenvs.create false --local && poetry install
COPY ${RELATIVE_CODE_PATH}/requirements.txt .
RUN python3.11 -m pip install -r requirements.txt --no-cache-dir

RUN ln -sf /usr/bin/python3.11 /usr/bin/python3 && \
	mkdir -p /usr/app/src/task_code && \
	mkdir -p /var/loggingConfiguration/spark/ && \
	touch /var/loggingConfiguration/spark/run-fluentd-spark.sh /var/loggingConfiguration/spark/run-adot-collector.sh
# ↑ If you don't pre-create /usr/app/src you'll hit a Java AccessDeniedException
# when EMR tries to copy the iceberg jar to the spark executors. The empty
# /var/loggingConfiguration/spark/ scripts exist so the image can also run
# locally (EMR Serverless mounts real versions at runtime).

WORKDIR /usr/app/src
COPY sandbox.ipynb .
COPY ${RELATIVE_CODE_PATH}/code/. /usr/app/src/task_code/
ENV PYTHONPATH /usr/app/src/task_code/:/usr/app/src/
RUN chown -R hadoop:hadoop /usr/app/src/

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
	AWS_DEFAULT_REGION=${AWS_REGION} \
    TASK_ADDITIONAL_PARAMETERS=${TASK_ADDITIONAL_PARAMETERS} \
    PYTHONUNBUFFERED=1

# EMRS will run the image as hadoop
USER hadoop:hadoop
