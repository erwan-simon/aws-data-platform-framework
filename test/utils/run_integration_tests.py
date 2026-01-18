import sys
import json
import time
import boto3


def main(state_machine_arn: str):
    sfn_client = boto3.client("stepfunctions")
    input_string = json.dumps({"hello": "world!"})
    sfn_execution_arn = sfn_client.start_execution(
        stateMachineArn=state_machine_arn, input=input_string
    )["executionArn"]
    print("Triggered step function, waiting for its end...")
    while True:
        sfn_execution_description = sfn_client.describe_execution(
            executionArn=sfn_execution_arn)
        if sfn_execution_description["status"] != "RUNNING":
            break
        time.sleep(60)
    if sfn_execution_description["status"] != "SUCCEEDED":
        raise ValueError(
            "Step function execution ended in "
            f"{sfn_execution_description['status']} state. -> "
            f"{sfn_execution_description['error']}: " +
            sfn_execution_description.get('cause', "No error cause given."))
    print("Step function execution ended in SUCCEEDED state.")


if __name__ == "__main__":
    main(sys.argv[1])
