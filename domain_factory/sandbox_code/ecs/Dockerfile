# syntax=docker/dockerfile:1

# ---- Builder stage ----
# python:3.13 (Debian + buildpack-deps) ships gcc/g++/make, enough for numpy
# 1.26.x to build from source (no cp313 wheel exists for that line).
# hadolint ignore=DL3029
FROM --platform=linux/amd64 python:3.13 AS builder
RUN pip3 install --no-cache-dir jupyter notebook poetry==2.1.4 papermill

WORKDIR /usr/app/src
ARG RELATIVE_CODE_PATH
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/pyproject.toml .
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/. .
RUN poetry config virtualenvs.create false --local && poetry install
COPY ${RELATIVE_CODE_PATH}/requirements.txt .
RUN pip install -r requirements.txt --no-cache-dir

# ---- Runtime stage ----
# python:3.13-slim drops buildpack-deps — same Debian Bookworm base, so
# compiled extensions copied from the builder stay ABI-compatible.
# hadolint ignore=DL3029
FROM --platform=linux/amd64 python:3.13-slim
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
# Poetry installs the root package in editable mode via a `.pth` in site-packages
# that points back to /usr/app/src/. We need the actual package files at that
# path for the indirection to resolve at runtime — without this COPY, `python -m
# datalake_sdk` fails with ModuleNotFoundError.
COPY --from=builder /usr/app/src/datalake_sdk /usr/app/src/datalake_sdk
RUN apt-get update && apt-get install -y --no-install-recommends awscli curl && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/app/src
COPY sandbox.ipynb .
ARG RELATIVE_CODE_PATH
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
