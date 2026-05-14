import uuid
import os
import logging
from datetime import datetime
import awswrangler as wr
from strands import Agent, tool
from strands.session.s3_session_manager import S3SessionManager
from strands.session.file_session_manager import FileSessionManager
from strands.agent.conversation_manager import SlidingWindowConversationManager
from strands.handlers.callback_handler import PrintingCallbackHandler
import click
from datalake_sdk.datalfred_agent.code_debugger import code_debugger_agent
from datalake_sdk.datalfred_agent.data_analyst import data_analyst_agent
from datalake_sdk.datalfred_agent.run_guy import run_guy_agent

from mcp.client.streamable_http import streamablehttp_client
from strands.tools.mcp import MCPClient

from strands_tools import file_read, file_write

# mcp_client = MCPClient(lambda: streamablehttp_client("http://127.0.0.1:8000/mcp"))

MAIN_SYSTEM_PROMPT = """
You are an assistant tasked to help users using the tools at your disposal.
You are in a datalake context, so it can be regarding accessing data in the datalake, do the run of an ingestion or look at the code of the datalake or of a processing job.
Here are some information that will be of some need:
- aws_region_name: '{aws_region_name}' (Name of the AWS region to use)
- current_date: '{current_date}' (today's date)
If the user ask you for an information that you think you do not have, always ask to the data analyst to search if the information is in the datalake.
IF A TOOL ENDS IN ERROR, PRINT THE ERROR AND DO NOT RETRY
"""


def calculate_conversation_costs(agent_instance: Agent, model_size: str) -> float:
    price_multiplicator_table = {
        "large": {"input": 0.000003, "output": 0.000015},
        "medium": {"input": 0.00000025, "output": 0.00000125},
        "small": {"input": 0.00000092, "output": 0.00000023},
    }
    conversation_total_costs = (
        agent_instance.state.get("total_input_tokens")
        * price_multiplicator_table[model_size]["input"]
        + agent_instance.state.get("total_output_tokens")
        * price_multiplicator_table[model_size]["output"]
    )
    return conversation_total_costs


def get_inference_profile_arn(
    logger, boto_session, inference_profile_prefix: str, model_size: str
) -> str:
    inference_profile_name = inference_profile_prefix + model_size
    inference_profile_list = boto_session.client("bedrock").list_inference_profiles(
        typeEquals="APPLICATION"
    )
    inference_profile_arn = None
    available_model_sizes_list = []
    for profile in inference_profile_list["inferenceProfileSummaries"]:
        if profile["inferenceProfileName"].startswith(inference_profile_prefix):
            available_model_sizes_list.append(
                profile["inferenceProfileName"].replace(inference_profile_prefix, "")
            )
            if profile["inferenceProfileName"] == inference_profile_name:
                inference_profile_arn = profile["inferenceProfileArn"]
    if not available_model_sizes_list:
        raise ValueError(
            f"No Bedrock inference profile found for '{inference_profile_prefix.rstrip('_')}'. "
            f"The LLM module is likely disabled on this domain "
            f"(set `enable_llm = true` on the domain_factory module to enable it)."
        )
    if not inference_profile_arn:
        raise ValueError(
            f"Did not find any inference profile with name {inference_profile_name}."
            f"Available model sizes: {available_model_sizes_list}"
        )
    logger.info(
        f"You set the model to '{model_size}'. "
        f"Other available sizes: {available_model_sizes_list}"
    )
    return inference_profile_arn


def instanciate_agent(
    logger,
    boto_session,
    datalfred_chatbot_strands_session_id: str,
    project_name: str,
    domain_name: str,
    stage_name: str,
    model_size: str,
    print_sub_agent_debug: bool,
    agent_callback_function,
    agent_state_additional_parameters: dict,
) -> Agent:
    inference_profile_prefix = f"{project_name}_{domain_name}_{stage_name}_"
    inference_profile_arn = get_inference_profile_arn(
        logger, boto_session, inference_profile_prefix, model_size
    )
    if datalfred_chatbot_strands_session_id:
        main_session_manager = S3SessionManager(
            session_id=datalfred_chatbot_strands_session_id,
            bucket=f"{inference_profile_prefix.replace('_', '-')}technical",
            prefix="datalfred_chatbot_strands_session",
            boto_session=boto_session,
        )
    else:
        # session will not be persisted
        main_session_manager = FileSessionManager(session_id=str(uuid.uuid1()))
    conversation_manager = SlidingWindowConversationManager(
        window_size=20,  # Maximum number of messages to keep
        should_truncate_results=True,  # Enable truncating the tool result when a message is too large for the model's context window
    )
    if not agent_callback_function:
        agent_callback_function = (
            PrintingCallbackHandler() if print_sub_agent_debug else None
        )
    agent = Agent(
        model=inference_profile_arn,
        system_prompt=MAIN_SYSTEM_PROMPT.format(
            aws_region_name=boto_session.region_name,
            current_date=datetime.now().strftime("%Y-%m-%d"),
        ),
        session_manager=main_session_manager,
        conversation_manager=conversation_manager,
        tools=[
            data_analyst_agent,
            run_guy_agent,
            code_debugger_agent,
            file_read,
            file_write,
        ],
        callback_handler=agent_callback_function,
    )
    agent.state.set("project_name", project_name)
    agent.state.set("domain_name", domain_name)
    agent.state.set("stage_name", stage_name)
    agent.state.set("inference_profile_arn", inference_profile_arn)
    agent.state.set("print_sub_agent_debug", print_sub_agent_debug)
    if agent_state_additional_parameters:
        for state_key, state_value in agent_state_additional_parameters.items():
            agent.state.set(state_key, state_value)
    return agent


def main(
    logger,
    boto_session,
    project_name: str,
    domain_name: str,
    stage_name: str,
    model_size: str,
    print_sub_agent_debug: bool,
    user_prompt: str = None,
    datalfred_chatbot_strands_session_id: str = None,
    agent_callback_function=None,
    agent_state_additional_parameters: dict = None,
) -> str:
    logging.getLogger("strands").setLevel(logging.INFO)
    logging.basicConfig(
        format="%(levelname)s | %(name)s | %(message)s",
        handlers=[logging.StreamHandler()],
    )
    agent = instanciate_agent(
        logger,
        boto_session,
        datalfred_chatbot_strands_session_id,
        project_name,
        domain_name,
        stage_name,
        model_size,
        print_sub_agent_debug,
        agent_callback_function,
        agent_state_additional_parameters,
    )
    token_usage = {"input": 0, "output": 0}
    message_to_return = None
    if not user_prompt:
        logger.info(
            "Welcome! I'm Datalfred, and I'm here to assist you in your usage of this "
            "data platform.\nType 'exit' to exit this conversation."
        )
        while True:
            try:
                user_prompt = input("\n\n>>> ")
            except Exception as error:
                logger.error(f"There was an error in your prompt: {error}")
                continue
            if user_prompt == "exit":
                break
            agent_response = agent(user_prompt)
            token_usage["input"] += agent_response.metrics.accumulated_usage[
                "inputTokens"
            ]
            token_usage["output"] += agent_response.metrics.accumulated_usage[
                "outputTokens"
            ]
    else:
        # using parameter sent user_prompt you can call this function for a one shot question instead of a conversation
        agent_response = agent(user_prompt)
        token_usage["input"] += agent_response.metrics.accumulated_usage["inputTokens"]
        token_usage["output"] += agent_response.metrics.accumulated_usage[
            "outputTokens"
        ]
        message_to_return = str(agent_response.message["content"][0]["text"])
    total_input_tokens = (
        agent.state.get("total_input_tokens")
        if agent.state.get("total_input_tokens")
        else 0
    )
    total_output_tokens = (
        agent.state.get("total_output_tokens")
        if agent.state.get("total_output_tokens")
        else 0
    )
    agent.state.set("total_input_tokens", total_input_tokens + token_usage["input"])
    agent.state.set("total_output_tokens", total_output_tokens + token_usage["output"])
    conversation_total_costs = calculate_conversation_costs(agent, model_size)
    logger.info(f"This conversation costed {conversation_total_costs:0.2f} dollars.")
    if model_size != "small" and float(f"{conversation_total_costs:0.2f}") > 0:
        small_model_total_cost = calculate_conversation_costs(agent, "small")
        logger.info(
            f"If you used a small model size instead of a {model_size} one, "
            f"it would have costed you {small_model_total_cost:0.2f} dollars instead "
            "(think about it next time)."
        )
    return message_to_return


@click.command("datalfred", short_help="LLM agent to query data and do ingestions run")
@click.option(
    "-s", "--model-size", required=False, default="small", help="Size of the model"
)
@click.option(
    "-d", "--print-sub-agent-debug", required=False, default=False, is_flag=True
)
@click.option("-id", "--session-id", required=False, default=None)
@click.option("-up", "--user-prompt", required=False, default=None)
@click.pass_context
def command_line_datalfred_agent(
    ctx,
    model_size="small",
    print_sub_agent_debug=False,
    session_id: str = None,
    user_prompt: str = None,
):
    response = main(
        ctx.obj.logger,
        ctx.obj.boto_session,
        ctx.obj.project_name,
        ctx.obj.domain_name,
        ctx.obj.stage_name,
        model_size=model_size,
        print_sub_agent_debug=print_sub_agent_debug,
        datalfred_chatbot_strands_session_id=session_id,
        user_prompt=user_prompt,
    )
    if response:
        print(response)
