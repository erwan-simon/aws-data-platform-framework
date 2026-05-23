import os
import logging
import json
import boto3
from datalake_sdk.slack import send_slack_message
from datalake_sdk.datalfred_agent.main import main as datalfred_main


def handle_ecs(
    logger: logging.Logger, environment_name: str, event: dict
) -> (str, str):
    step_function_task_token = [
        environment_variable_dict["value"]
        for environment_variable_dict in event["detail"]["overrides"][
            "containerOverrides"
        ][0]["environment"]
        if environment_variable_dict["name"] == "step_function_task_token"
    ][0]
    try:
        error_message = event["detail"]["lastStatus"]
        task_name = (
            event["detail"]["clusterArn"]
            .split(":")[-1]
            .replace(f"cluster/{environment_name}_", "")
        )
        if event["detail"]["stopCode"] != "EssentialContainerExited":
            exit_status_code = event["detail"]["stopCode"]
            task_error_message = event["detail"]["stoppedReason"]
        else:
            exit_status_code = event["detail"]["containers"][0]["exitCode"]
            if exit_status_code == 0:
                # We still need to catch this cloudwatch event because we
                # cannot filter on containers exit code being different than
                # 0 because when the error is TaskFailedToStart (for example
                # if it could not pull the docker image), there is no
                # container exit code
                logger.info("ECS task did not fail.")
                return step_function_task_token, None
            task_error_message = event["detail"]["containers"][0].get(
                "reason",
                event["detail"]["stoppedReason"]
                + " (Found no more precise error message)",
            )
        error_message = (
            f"ECS task {task_name} ended in STOPPED state with"
            + f" status code '{exit_status_code}': {task_error_message}"
        )
    except KeyError as error:
        error_message = (
            f"Platform error: Did not find key '{error}' " + "in ECS stopping event"
        )
        logger.error(error_message)
    except Exception as error:
        error_message = f"Platform error: {error}"
        logger.error(error_message)
    return step_function_task_token, error_message


def handle_emr_serverless(
    _: logging.Logger, environment_name: str, event: dict
) -> (str, str):
    emr_serverless_client = boto3.client("emr-serverless")
    job_run_config = emr_serverless_client.get_job_run(
        applicationId=event["detail"]["applicationId"],
        jobRunId=event["detail"]["jobRunId"],
    )["jobRun"]
    application_config = emr_serverless_client.get_application(
        applicationId=job_run_config["applicationId"]
    )["application"]
    task_name = application_config["name"].replace(f"{environment_name}_", "")
    entrypoint_arguments = json.loads(
        job_run_config["jobDriver"]["sparkSubmit"]["entryPointArguments"][0]
    )
    step_function_task_token = entrypoint_arguments["step_function_task_token"]
    task_error_message = job_run_config.get(
        "stateDetails", "No state details found in EMR job run"
    )
    error = (
        f"EMR task {task_name} ended in {job_run_config['state']} state: "
        + task_error_message
    )
    return step_function_task_token, error


TRIAGE_DICT = {"aws.ecs": handle_ecs, "aws.emr-serverless": handle_emr_serverless}


def investigate_error_with_datalfred(
    logger, boto_session, project_name: str, domain_name: str, stage_name: str
) -> str:
    model_size = os.environ["FAILURE_INVESTIGATION_MODEL_SIZE"]
    print_sub_agent_debug = True
    return datalfred_main(
        logger,
        boto_session,
        project_name,
        domain_name,
        stage_name,
        model_size,
        print_sub_agent_debug,
        f"The latest pipeline run for project {project_name}, domain {domain_name}, "
        f"stage {stage_name} just failed. Find the latest failure (ignore previous ones) "
        "and explain briefly why it failed. If you identify a fix, describe it briefly. "
        "Respond with a short synthetic paragraph formatted for Slack — no greeting, no "
        "header, just the analysis text (it will be inlined under a 'Datalfred bug "
        "analysis:' field in a larger Slack message).",
    )


def main(event: dict, _: dict):
    project_name = os.environ["PROJECT_NAME"]
    domain_name = os.environ["DOMAIN_NAME"]
    stage_name = os.environ["STAGE_NAME"]
    environment_name = f"{project_name}_{domain_name}_{stage_name}"
    logger = logging.getLogger()
    logging.basicConfig(level=logging.INFO, format="%(message)s", force=True)
    logger.info(event)
    try:
        step_function_task_token, error_message = TRIAGE_DICT[event["source"]](
            logger, environment_name, event
        )
    except KeyError as error:
        raise ValueError(f"Unknown event source: {event['source']}") from error
    if event.get("dry_run") is True:
        # Smoke test path: prove the function loads, parses the event and
        # constructs its boto3 clients without actually aborting the SFN or
        # paging anyone. See scripts/failsafe_lambda_smoke_test.sh.
        logger.info("dry_run mode — skipping send_task_failure and slack notification")
        return {"status": "dry_run_ok", "parsed_error": error_message}
    if not error_message:
        # task did not really fail, false alarm
        return
    logger.info(f"Aborting step function execution: {error_message}")
    sfn_client = boto3.client("stepfunctions")
    slack_message = f"Pipeline failure on {environment_name}:\n{error_message}"
    if os.environ.get("LLM_ENABLED", "true").lower() == "true":
        try:
            analysis = investigate_error_with_datalfred(
                logger, boto3.session.Session(), project_name, domain_name, stage_name
            )
            slack_message += f"\n\nDatalfred bug analysis: {analysis}"
        except Exception as error:
            logger.error(
                "The datalfred investigation did not seem to work: " + str(error)
            )
    else:
        logger.info(
            "LLM module disabled on this domain — skipping datalfred investigation."
        )
    try:
        send_slack_message(project_name, slack_message)
    except Exception as error:
        # if the slack integration is not implemented, we do not want this lambda function to fail
        logger.error("Failed to send slack notification: " + str(error))
    # error parameter string size is capped to 256 characters
    try:
        sfn_client.send_task_failure(
            taskToken=step_function_task_token, error=error_message[:250] + "..."
        )
    except Exception as error:
        if "TaskTimedOut" not in str(error):
            raise error
        logger.info("Step function is already stopped")
