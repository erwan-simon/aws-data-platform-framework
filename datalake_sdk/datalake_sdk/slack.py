import json
import boto3
import click
from slack_sdk import WebClient


def send_slack_message(project_name: str, message_content: str, channel_id: str=None, unfurl_links: bool=True) -> str:
    boto_session = boto3.session.Session()
    secretsmanager_client = boto_session.client("secretsmanager")
    secret_id = f"{project_name}_slack_alerting_prod"
    slack_info = json.loads(
        secretsmanager_client.get_secret_value(
            SecretId=secret_id)["SecretString"]
        )
    channel_id = channel_id if channel_id else slack_info.get("slack_channel_id")
    if not channel_id:
        raise ValueError(f"Did not find any slack channel in secret {secret_id} nor in sent parameters.")
    slack_client = WebClient(token=slack_info["token"])
    slack_client.chat_postMessage(
        channel=channel_id, text=message_content, unfurl_links=unfurl_links)


@click.group()
@click.option(
    "-c", '--channel-id', required=False,
    help="ID of the Slack channel to which send the message."
    " If not given will use 'slack_channel_id' value in the secret")
@click.option(
    "-m", '--message-content', required=True,
    help="Message to send to slack")
@click.pass_context
def command_line_send_slack_message(context: click.Context, message_content: str, channel_id: str) -> None:
    send_slack_message(context.obj.project_name, message_content, channel_id)
