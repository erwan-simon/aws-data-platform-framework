from pathlib import Path
import os
import ast
from strands import Agent, tool
from strands.types.tools import ToolContext
from strands.handlers.callback_handler import PrintingCallbackHandler


@tool
def analyze_python_file(file_path: str) -> dict:
    """
    Analyzes a Python (.py) file and extracts information about its
    module-level docstring, functions, and classes. For each function,
    it retrieves the name, list of arguments, and docstring. For each
    class, it retrieves the name and docstring.

    Args:
        file_path (str): Path to the Python file to analyze.

    Returns:
        dict: A dictionary containing the following keys:
            - "module_docstring" (str or None): Docstring of the module, if present.
            - "functions" (list of dict): List of functions, each with:
                - "name" (str): Function name.
                - "args" (list of str): Names of the function arguments.
                - "docstring" (str or None): Docstring of the function.
            - "classes" (list of dict): List of classes, each with:
                - "name" (str): Class name.
                - "docstring" (str or None): Docstring of the class.
    """
    with open(file_path, "r", encoding="utf-8") as f:
        source = f.read()

    tree = ast.parse(source, filename=file_path)

    functions_info = []
    classes_info = []

    for node in ast.walk(tree):
        # Fonctions globales ou dans des classes
        if isinstance(node, ast.FunctionDef):
            func_name = node.name
            args = [arg.arg for arg in node.args.args]
            docstring = ast.get_docstring(node)
            functions_info.append(
                {"name": func_name, "args": args, "docstring": docstring}
            )

        # Classes
        if isinstance(node, ast.ClassDef):
            class_name = node.name
            docstring = ast.get_docstring(node)
            classes_info.append({"name": class_name, "docstring": docstring})

    return {
        "functions": functions_info,
        "classes": classes_info,
        "module_docstring": ast.get_docstring(tree),
    }


@tool
def read_file_as_string(file_path: str) -> str:
    """
    Reads the content of a file and returns it as a string.

    Args:
        file_path (str): Path to the file to read.

    Returns:
        str: Content of the file as a single string.
    """
    path = Path(file_path)
    if not path.is_file():
        raise FileNotFoundError(
            f"The file '{file_path}' does not exist or is not a file."
        )
    return path.read_text(encoding="utf-8")


@tool
def get_tree(start_path: str) -> dict:
    """
    Builds a nested dictionary representing the directory tree starting
    from the given directory path. Each directory is represented as a
    dictionary with its name, type, and children. Each file is represented
    as a dictionary with its name and type.

    Args:
        directory (Path): Path object pointing to the root directory to scan.

    Returns:
        dict: A nested dictionary representing the directory tree structure.
    """
    directory = Path(start_path)
    tree = {"name": directory.name, "type": "directory", "children": []}
    for entry in sorted(
        directory.iterdir(), key=lambda e: (e.is_file(), e.name.lower())
    ):
        if entry.is_dir():
            tree["children"].append(get_tree(entry))
        else:
            tree["children"].append({"name": entry.name, "type": "file"})
    return tree


CODE_DEBUGGER_SYSTEM_PROMPT = """
You are an assistant tasked to help users using the tools at your disposal.
You can find the pipeline terraform configurations in the ./iac/ directory, in the pipeline configurations you will find the definition of each tasks, and in it the path in which is the code of the task.
If you think it relevant do not hesitate to read the code of the tasks.
You also can find the configuration of the step function in the .tftpl.json files
Right now you are in the {current_path} directory.
"""


@tool(context=True)
def code_debugger_agent(main_agent, user_prompt: str, tool_context: ToolContext):
    """
    Function which runs an assistant whose role is to investigate problems about the datalake or its ingestion in the code.
    This agent CANNOT be used to access to data from the datalake.


    Args:
        main_agent (strands.Agent): instance of the main strands agent
        user_prompt (str): question of the user

    Returns:
        str: response of the agent to the user question
    """
    if "CODE_DEBUGGER_AGENT" not in globals():
        global CODE_DEBUGGER_AGENT
        CODE_DEBUGGER_AGENT = Agent(
            model=tool_context.agent.state.get("inference_profile_arn"),
            system_prompt=CODE_DEBUGGER_SYSTEM_PROMPT.format(current_path=os.getcwd()),
            callback_handler=PrintingCallbackHandler()
            if tool_context.agent.state.get("print_sub_agent_debug")
            else None,
            tools=[get_tree, read_file_as_string, analyze_python_file],
        )
    agent_response = CODE_DEBUGGER_AGENT(user_prompt)
    total_input_tokens = (
        tool_context.agent.state.get("total_input_tokens")
        if tool_context.agent.state.get("total_input_tokens")
        else 0
    )
    total_output_tokens = (
        tool_context.agent.state.get("total_output_tokens")
        if tool_context.agent.state.get("total_output_tokens")
        else 0
    )
    tool_context.agent.state.set(
        "total_output_tokens",
        total_output_tokens + agent_response.metrics.accumulated_usage["outputTokens"],
    )
    tool_context.agent.state.set(
        "total_input_tokens",
        total_input_tokens + agent_response.metrics.accumulated_usage["inputTokens"],
    )
    return agent_response
