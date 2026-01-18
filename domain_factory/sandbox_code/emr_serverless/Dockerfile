# syntax=docker/dockerfile:1
FROM --platform=linux/amd64 public.ecr.aws/emr-serverless/spark/emr-7.1.0:20240823

# https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/application-custom-image.html

USER root
# MODIFICATIONS GO HERE

# install python 3.10
RUN yum install -y gcc openssl-devel bzip2-devel sqlite-devel libffi-devel tar gzip wget make zlib-static && \
	yum clean all && \
  wget https://www.python.org/ftp/python/3.13.7/Python-3.13.7.tgz && \
	tar xzf Python-3.13.7.tgz && cd Python-3.13.7 && \
	./configure --enable-optimizations --enable-loadable-sqlite-extensions && \
	make altinstall && \
	ln -sf /usr/local/bin/python3.13 /usr/bin/python3 && \
	ln -sf /usr/bin/pip3 /usr/bin/pip && \
	pip3 install --no-cache-dir poetry==2.1.4

# If you don't do that you will have a Java AccessDeniedException when trying to copy the iceberg jar file to the /usr/app/src directory in the spark executors instances
RUN mkdir -p /usr/app/src/task_code
WORKDIR /usr/app/src

# setup jupyter notebook for local execution
RUN pip install jupyter notebook
# the following line is to setup files required by the source docker image which are mounted directly by EMR Serverless service. We create empty file because we want to be able to run this image locally, and the scripts do not really need to do anything in this context
RUN mkdir -p /var/loggingConfiguration/spark/ && touch /var/loggingConfiguration/spark/run-fluentd-spark.sh && touch /var/loggingConfiguration/spark/run-adot-collector.sh

COPY sandbox.ipynb .
ARG RELATIVE_CODE_PATH
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/pyproject.toml .
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/. .
RUN poetry config virtualenvs.create false --local && poetry install
COPY ${RELATIVE_CODE_PATH}/requirements.txt .
RUN pip install -r requirements.txt --no-cache-dir
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
    TASK_ADDITIONAL_PARAMETERS=${TASK_ADDITIONAL_PARAMETERS}

# end of modifications
# EMRS will run the image as hadoop

USER hadoop:hadoop
