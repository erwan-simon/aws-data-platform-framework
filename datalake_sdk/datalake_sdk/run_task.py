import json
import time
import uuid
from typing import Optional

import click


ECS_RESOURCE = "arn:aws:states:::aws-sdk:ecs:runTask.waitForTaskToken"
EMR_RESOURCE = "arn:aws:states:::aws-sdk:emrserverless:startJobRun.waitForTaskToken"


def _find_state(states: dict, target_name: str) -> Optional[dict]:
    """Walk a Step Functions definition recursively and return the state
    whose name matches ``target_name`` (handles nested Parallel/Map)."""
    for name, state in states.items():
        if name == target_name:
            return state
        if state.get("Type") == "Parallel":
            for branch in state.get("Branches", []):
                found = _find_state(branch.get("States", {}), target_name)
                if found:
                    return found
        elif state.get("Type") == "Map":
            iterator = state.get("ItemProcessor") or state.get("Iterator") or {}
            found = _find_state(iterator.get("States", {}), target_name)
            if found:
                return found
    return None


def _pascal_to_camel_keys(obj):
    """Recursively convert dict keys from PascalCase to camelCase (lowercase
    first letter only). Strips Step-Functions ``.$`` suffix from keys."""
    if isinstance(obj, dict):
        out = {}
        for key, value in obj.items():
            clean_key = key[:-2] if key.endswith(".$") else key
            new_key = clean_key[:1].lower() + clean_key[1:] if clean_key else clean_key
            out[new_key] = _pascal_to_camel_keys(value)
        return out
    if isinstance(obj, list):
        return [_pascal_to_camel_keys(v) for v in obj]
    return obj


def _is_sfn_intrinsic(value) -> bool:
    if not isinstance(value, str):
        return False
    return (
        value.startswith("$$.") or value.startswith("$.") or value.startswith("States.")
    )


def _clean_ecs_env(environment: list, logger) -> list:
    cleaned = []
    for entry in environment:
        if "Value.$" in entry:
            value = entry["Value.$"]
            if _is_sfn_intrinsic(value):
                logger.info(
                    f"Dropping SFN-bound env var '{entry.get('Name')}' "
                    f"(value '{value}' is an intrinsic)"
                )
                continue
            cleaned.append({"name": entry["Name"], "value": value})
        else:
            cleaned.append({"name": entry["Name"], "value": entry["Value"]})
    return cleaned


def _build_ecs_run_task_kwargs(state: dict, logger) -> dict:
    params = state["Parameters"]
    overrides = params.get("Overrides", {})
    container_overrides = []
    for co in overrides.get("ContainerOverrides", []):
        container_overrides.append(
            {
                "name": co["Name"],
                "environment": _clean_ecs_env(co.get("Environment", []), logger),
            }
        )
    network = params["NetworkConfiguration"]["AwsvpcConfiguration"]
    return {
        "cluster": params["Cluster"],
        "taskDefinition": params["TaskDefinition"],
        "launchType": params.get("LaunchType", "FARGATE"),
        "count": 1,
        "clientToken": uuid.uuid4().hex,
        "propagateTags": params.get("PropagateTags", "TASK_DEFINITION"),
        "overrides": {"containerOverrides": container_overrides},
        "networkConfiguration": {
            "awsvpcConfiguration": {
                "subnets": network["Subnets"],
                "securityGroups": network["SecurityGroups"],
                "assignPublicIp": network.get("AssignPublicIp", "DISABLED"),
            }
        },
    }


def _build_emr_start_job_kwargs(state: dict, logger) -> dict:
    params = state["Parameters"]
    spark = params["JobDriver"]["SparkSubmit"]
    raw_args = spark.get("EntryPointArguments", [])
    cleaned_args = []
    for arg in raw_args:
        if isinstance(arg, dict):
            keep = {}
            for key, value in arg.items():
                clean_key = key[:-2] if key.endswith(".$") else key
                if _is_sfn_intrinsic(value):
                    logger.info(
                        f"Dropping SFN-bound spark arg '{clean_key}' "
                        f"(value '{value}' is an intrinsic)"
                    )
                    continue
                keep[clean_key] = value
            cleaned_args.append(json.dumps(keep))
        else:
            cleaned_args.append(arg)
    return {
        "applicationId": params["ApplicationId"],
        "clientToken": uuid.uuid4().hex,
        "executionRoleArn": params["ExecutionRoleArn"],
        "name": f"manual-{uuid.uuid4().hex[:8]}",
        "tags": params.get("Tags", {}),
        "executionTimeoutMinutes": params.get("ExecutionTimeoutMinutes", 0),
        "jobDriver": {
            "sparkSubmit": {
                "entryPoint": spark["EntryPoint"],
                "entryPointArguments": cleaned_args,
                "sparkSubmitParameters": spark.get("SparkSubmitParameters", ""),
            }
        },
        "configurationOverrides": _pascal_to_camel_keys(
            params.get("ConfigurationOverrides", {})
        ),
    }


def _print_log_group(boto_session, log_group: str, logger) -> None:
    region = boto_session.region_name
    encoded = log_group.replace("/", "$252F")
    logger.info(f"Log group: {log_group}")
    logger.info(
        f"Console: https://{region}.console.aws.amazon.com/cloudwatch/home"
        f"?region={region}#logsV2:log-groups/log-group/{encoded}"
    )


def _print_log_events(boto_session, log_group: str, start_time_ms: int, logger) -> None:
    logs_client = boto_session.client("logs")
    logger.info(f"--- CloudWatch logs ({log_group}) ---")
    try:
        paginator = logs_client.get_paginator("filter_log_events")
        empty = True
        for page in paginator.paginate(logGroupName=log_group, startTime=start_time_ms):
            for event in page.get("events", []):
                empty = False
                logger.info(event.get("message", "").rstrip())
        if empty:
            logger.info("(no log events)")
    except logs_client.exceptions.ResourceNotFoundException:
        logger.info(f"Log group {log_group} not found")
    except Exception as exc:  # noqa: BLE001
        logger.info(f"Failed to fetch logs: {exc}")
    logger.info("--- end of logs ---")


def _run_ecs(boto_session, state, environment_name, pipeline_name, task_name, logger):
    ecs_client = boto_session.client("ecs")
    kwargs = _build_ecs_run_task_kwargs(state, logger)
    logger.info(f"Starting ECS task on cluster {kwargs['cluster']}")
    start_time_ms = int(time.time() * 1000)
    response = ecs_client.run_task(**kwargs)
    failures = response.get("failures", [])
    if failures:
        raise click.ClickException(f"ECS run_task failed: {failures}")
    task_arn = response["tasks"][0]["taskArn"]
    logger.info(f"ECS task started: {task_arn}")
    log_group = f"{environment_name}_{pipeline_name}/{task_name}"
    _print_log_group(boto_session, log_group, logger)

    last_status = None
    while True:
        described = ecs_client.describe_tasks(
            cluster=kwargs["cluster"], tasks=[task_arn]
        )
        if not described["tasks"]:
            time.sleep(5)
            continue
        task = described["tasks"][0]
        status = task.get("lastStatus")
        if status != last_status:
            logger.info(f"ECS task status: {status}")
            last_status = status
        if status == "STOPPED":
            container = (task.get("containers") or [{}])[0]
            logger.info(
                f"ECS task STOPPED (stopCode={task.get('stopCode')}, "
                f"exitCode={container.get('exitCode')}, "
                f"reason={task.get('stoppedReason')})"
            )
            _print_log_events(boto_session, log_group, start_time_ms, logger)
            return
        time.sleep(5)


def _run_emr(boto_session, state, environment_name, pipeline_name, task_name, logger):
    emr_client = boto_session.client("emr-serverless")
    kwargs = _build_emr_start_job_kwargs(state, logger)
    logger.info(f"Starting EMR Serverless job on application {kwargs['applicationId']}")
    start_time_ms = int(time.time() * 1000)
    response = emr_client.start_job_run(**kwargs)
    job_run_id = response["jobRunId"]
    logger.info(f"EMR Serverless job started: {job_run_id}")
    log_group = f"{environment_name}_{pipeline_name}/{task_name}"
    _print_log_group(boto_session, log_group, logger)

    last_state = None
    while True:
        job = emr_client.get_job_run(
            applicationId=kwargs["applicationId"], jobRunId=job_run_id
        )["jobRun"]
        current = job.get("state")
        if current != last_state:
            logger.info(f"EMR job state: {current}")
            last_state = current
        if current in {"SUCCESS", "FAILED", "CANCELLED"}:
            logger.info(
                f"EMR job finished: state={current}, detail={job.get('stateDetails')}"
            )
            _print_log_events(boto_session, log_group, start_time_ms, logger)
            return
        time.sleep(10)


@click.command(
    "run_task",
    short_help="Run a single task of a pipeline standalone (no Step Functions execution)",
)
@click.pass_context
@click.option("-pn", "--pipeline-name", required=True, help="Pipeline name")
@click.option("-tn", "--task-name", required=True, help="Task name (state name)")
def command_line_run_task(ctx, pipeline_name: str, task_name: str):
    boto_session = ctx.obj.boto_session
    logger = ctx.obj.logger
    environment_name = (
        f"{ctx.obj.project_name}_{ctx.obj.domain_name}_{ctx.obj.stage_name}"
    )
    state_machine_name = f"{environment_name}_{pipeline_name}"
    account_id = boto_session.client("sts").get_caller_identity()["Account"]
    region = boto_session.region_name
    state_machine_arn = (
        f"arn:aws:states:{region}:{account_id}:stateMachine:{state_machine_name}"
    )
    sfn_client = boto_session.client("stepfunctions")
    logger.info(f"Reading state machine definition: {state_machine_arn}")
    definition = json.loads(
        sfn_client.describe_state_machine(stateMachineArn=state_machine_arn)[
            "definition"
        ]
    )
    state = _find_state(definition.get("States", {}), task_name)
    if state is None:
        raise click.UsageError(
            f"Task '{task_name}' not found in state machine '{state_machine_name}'."
        )
    resource = state.get("Resource", "")
    if resource == ECS_RESOURCE:
        _run_ecs(
            boto_session, state, environment_name, pipeline_name, task_name, logger
        )
    elif resource == EMR_RESOURCE:
        _run_emr(
            boto_session, state, environment_name, pipeline_name, task_name, logger
        )
    else:
        raise click.UsageError(
            f"Task '{task_name}' has unsupported Resource '{resource}'."
        )
