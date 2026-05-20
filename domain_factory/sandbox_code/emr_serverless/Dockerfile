# syntax=docker/dockerfile:1
# https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/application-custom-image.html

# ---- Builder stage ----
# Compiles Python 3.13 from source (no python3.13 package on the EMR base
# image) plus the SDK and its deps. Toolchain + dev headers + tarball stay
# in this stage; only /usr/local lands in the runtime image.
FROM --platform=linux/amd64 public.ecr.aws/emr-serverless/spark/emr-7.1.0:20240823 AS builder
USER root

RUN yum install -y gcc gcc-c++ openssl-devel bzip2-devel sqlite-devel libffi-devel tar gzip wget make zlib-static && \
	yum clean all && \
	wget https://www.python.org/ftp/python/3.13.7/Python-3.13.7.tgz && \
	tar xzf Python-3.13.7.tgz && cd Python-3.13.7 && \
	./configure --enable-optimizations --enable-loadable-sqlite-extensions && \
	make altinstall && \
	cd / && rm -rf Python-3.13.7 Python-3.13.7.tgz && \
	/usr/local/bin/pip3.13 install --no-cache-dir poetry==2.1.4 jupyter notebook

WORKDIR /usr/app/src
ARG RELATIVE_CODE_PATH
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/pyproject.toml .
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/. .
RUN /usr/local/bin/poetry config virtualenvs.create false --local && /usr/local/bin/poetry install
COPY ${RELATIVE_CODE_PATH}/requirements.txt .
RUN /usr/local/bin/pip3.13 install -r requirements.txt --no-cache-dir

# ---- Runtime stage ----
# Same EMR base, no toolchain. Pull the compiled Python interpreter + all
# resolved site-packages from the builder.
FROM --platform=linux/amd64 public.ecr.aws/emr-serverless/spark/emr-7.1.0:20240823
USER root
COPY --from=builder /usr/local /usr/local
# Poetry installs the root package in editable mode via a `.pth` in site-packages
# that points back to /usr/app/src/. We need the actual package files at that
# path for the indirection to resolve at runtime — without this COPY, `python -m
# datalake_sdk` fails with ModuleNotFoundError.
COPY --from=builder /usr/app/src/datalake_sdk /usr/app/src/datalake_sdk

RUN ln -sf /usr/local/bin/python3.13 /usr/bin/python3 && \
	ln -sf /usr/local/bin/pip3.13 /usr/bin/pip && \
	mkdir -p /usr/app/src/task_code && \
	mkdir -p /var/loggingConfiguration/spark/ && \
	touch /var/loggingConfiguration/spark/run-fluentd-spark.sh /var/loggingConfiguration/spark/run-adot-collector.sh
# ↑ If you don't pre-create /usr/app/src you'll hit a Java AccessDeniedException
# when EMR tries to copy the iceberg jar to the spark executors. The empty
# /var/loggingConfiguration/spark/ scripts exist so the image can also run
# locally (EMR Serverless mounts real versions at runtime).

WORKDIR /usr/app/src
COPY sandbox.ipynb .
ARG RELATIVE_CODE_PATH
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

# EMRS will run the image as hadoop
USER hadoop:hadoop
