# syntax=docker/dockerfile:1

# ---- Builder stage ----
# `--extras agent` pulls strands-agents → libcst, whose linux wheels are
# manylinux_2_28-only (glibc 2.28+) — but the Lambda Python 3.11 base is
# Amazon Linux 2 (glibc 2.26), so libcst falls back to a Rust source build.
# We keep a builder stage with the toolchain and ship only the resolved
# site-packages to the runtime.
FROM --platform=linux/amd64 public.ecr.aws/lambda/python:3.11 AS builder
# Toolchain packages on AL2 — pinning gcc/cargo/rust across base image bumps is brittle, kept unversioned.
# hadolint ignore=DL3033
RUN yum install -y gcc gcc-c++ make rust cargo && yum clean all
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
FROM --platform=linux/amd64 public.ecr.aws/lambda/python:3.11
COPY --from=builder /var/lang/lib/python3.11/site-packages /var/lang/lib/python3.11/site-packages
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
    TASK_ADDITIONAL_PARAMETERS=${TASK_ADDITIONAL_PARAMETERS}
