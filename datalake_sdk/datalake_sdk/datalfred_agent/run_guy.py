from strands.handlers.callback_handler import PrintingCallbackHandler
from strands.types.tools import ToolContext
from strands import Agent, tool
from strands_tools import use_aws

RUN_GUY_SYSTEM_PROMPT = """
You are an assistant which can investigate problems about the datalake in AWS. There is jobs that put data in the datalake. Those jobs run using ECS Fargate tasks or EMR Serverless, depending on the tasks.
The tasks in a pipeline are orchestrated using step functions.
The logs of the tasks are in cloudwatch. You can find the relevant log group url (hence name) in the task definition in the step function.
YOU MUST NEVER MODIFY ANYTHING IN AWS, THIS IS VERY IMPORTANT.
The only thing you can do is redrive a failed step function if it is EXPLICITELY ASKED BY THE USER.
Always consider you are in the {aws_region_name} AWS region
"""

@tool(context=True)
def run_guy_agent(main_agent, user_prompt: str, aws_region_name: str, tool_context: ToolContext):
    """
    Function which runs an assistant whose role is to investigate problems about the datalake in AWS, or to get information about ingestions status.
    This agent CANNOT be used to access to data from the datalake.
    This agent CANNOT be used to modify resources in AWS.

    Args:
        main_agent (strands.Agent): instance of the main strands agent
        inference_profile_arn (str): ARN of the bedrock inference profile
        user_prompt (str): question of the user
        aws_region_name (str): Name of the AWS region

    Returns:
        str: response of the agent to the user question
    """
    if "RUN_GUY_AGENT" not in globals():
        global RUN_GUY_AGENT
        RUN_GUY_AGENT = Agent(
            model=tool_context.agent.state.get("inference_profile_arn"),
            system_prompt=RUN_GUY_SYSTEM_PROMPT.format(aws_region_name=aws_region_name),
            callback_handler=PrintingCallbackHandler()
            if tool_context.agent.state.get("print_sub_agent_debug") else None,
            tools=[use_aws])
    agent_response = RUN_GUY_AGENT(user_prompt)
    total_input_tokens = tool_context.agent.state.get("total_input_tokens") if tool_context.agent.state.get("total_input_tokens") else 0
    total_output_tokens = tool_context.agent.state.get("total_output_tokens") if tool_context.agent.state.get("total_output_tokens") else 0
    tool_context.agent.state.set(
        "total_output_tokens",
        total_output_tokens + agent_response.metrics.accumulated_usage["outputTokens"])
    tool_context.agent.state.set(
        "total_input_tokens",
        total_input_tokens + agent_response.metrics.accumulated_usage["inputTokens"])
    return agent_response
