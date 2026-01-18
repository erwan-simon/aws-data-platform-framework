FROM --platform=linux/amd64 public.ecr.aws/lambda/python:3.13
RUN pip3 install --no-cache-dir poetry==2.1.4
WORKDIR $LAMBDA_TASK_ROOT/
CMD [ "task_code.main.main" ]
ARG RELATIVE_CODE_PATH
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/pyproject.toml .
COPY ${RELATIVE_CODE_PATH}/datalake_sdk/. .
RUN poetry config virtualenvs.create false --local && poetry install --extras agent
COPY ${RELATIVE_CODE_PATH}/requirements.txt .
RUN pip install -r requirements.txt --no-cache-dir
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
