from datalake_sdk.base_processing_wrapper import BaseProcessingWrapper
from shared_lib.main import build_mock_dataframe


def main(job: BaseProcessingWrapper):
    dataframe = build_mock_dataframe()
    return {
        "{{cookiecutter.domain_name}}.mock_data": job.ProcessingResponse(
            dataframe=dataframe,
        ),
    }
