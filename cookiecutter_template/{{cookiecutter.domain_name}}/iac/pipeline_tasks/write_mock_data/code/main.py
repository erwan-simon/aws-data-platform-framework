import pandas as pd
from datalake_sdk.base_processing_wrapper import BaseProcessingWrapper


def main(job: BaseProcessingWrapper):
    dataframe = pd.DataFrame(
        [
            {"id": 1, "name": "alice", "value": 10},
            {"id": 2, "name": "bob", "value": 20},
            {"id": 3, "name": "carol", "value": 30},
        ]
    )
    return {
        "{{cookiecutter.domain_name}}.mock_data": job.ProcessingResponse(
            dataframe=dataframe,
        ),
    }
