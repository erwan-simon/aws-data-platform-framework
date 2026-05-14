import pandas as pd


def build_mock_dataframe() -> pd.DataFrame:
    """Toy helper used by the starter pipeline. Replace with your own shared logic."""
    return pd.DataFrame(
        [
            {"id": 1, "name": "alice", "value": 10},
            {"id": 2, "name": "bob", "value": 20},
            {"id": 3, "name": "carol", "value": 30},
        ]
    )
