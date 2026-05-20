"""Build a pandera DataFrameSchema from a tables_configuration YAML dict.

Authoring lives in `<task>/code/tables_configuration/<db>.<table>.yaml`. The same
YAML carries Glue descriptions (already used elsewhere) and — when a column
declares a `type:` — feeds validation. Validation is opt-in per column.

Only built-in Pandera Field/Check params are accepted (no lambdas), so the
resulting schema stays roundtrip-serializable via `.to_json()` / `from_json()`.
"""

import re
from typing import Any, Callable, Dict, List, Optional

import pandera.pandas as pa


_SIMPLE_TYPES: Dict[str, Any] = {
    "string": pa.String,
    "int": pa.Int32,
    "bigint": pa.Int64,
    "float": pa.Float32,
    "double": pa.Float64,
    "boolean": pa.Bool,
    "date": pa.Date,
    "timestamp": pa.Timestamp,
}

_DECIMAL_RE = re.compile(r"^decimal\(\s*(\d+)\s*,\s*(\d+)\s*\)$")


def _resolve_type(type_str: str, column_name: str) -> Any:
    if type_str in _SIMPLE_TYPES:
        return _SIMPLE_TYPES[type_str]
    match = _DECIMAL_RE.match(type_str)
    if match:
        return pa.Decimal(int(match.group(1)), int(match.group(2)))
    supported = ", ".join(sorted(_SIMPLE_TYPES)) + ", decimal(p,s)"
    raise ValueError(
        f"Unknown column type '{type_str}' on column '{column_name}'. "
        f"Supported: {supported}."
    )


_CHECK_BUILDERS: Dict[str, Callable[[Any], pa.Check]] = {
    "ge": pa.Check.greater_than_or_equal_to,
    "gt": pa.Check.greater_than,
    "le": pa.Check.less_than_or_equal_to,
    "lt": pa.Check.less_than,
    "eq": pa.Check.equal_to,
    "isin": pa.Check.isin,
    "notin": pa.Check.notin,
    "str_startswith": pa.Check.str_startswith,
    "str_endswith": pa.Check.str_endswith,
    "str_matches": pa.Check.str_matches,
    "str_contains": pa.Check.str_contains,
}

_NON_VALIDATION_KEYS = {"description", "type"}
_COLUMN_FLAGS = {"nullable", "unique"}


def _build_column(column_name: str, column_dict: Dict[str, Any]) -> pa.Column:
    dtype = _resolve_type(column_dict["type"], column_name)
    checks: List[pa.Check] = []
    nullable = True
    unique = False
    for key, value in column_dict.items():
        if key in _NON_VALIDATION_KEYS:
            continue
        if key == "nullable":
            nullable = bool(value)
            continue
        if key == "unique":
            unique = bool(value)
            continue
        builder = _CHECK_BUILDERS.get(key)
        if builder is None:
            supported = ", ".join(
                sorted(_NON_VALIDATION_KEYS | _COLUMN_FLAGS | _CHECK_BUILDERS.keys())
            )
            raise ValueError(
                f"Unknown YAML keyword '{key}' under column '{column_name}'. "
                f"Supported keys: {supported}."
            )
        checks.append(builder(value))
    return pa.Column(
        dtype,
        checks=checks or None,
        nullable=nullable,
        unique=unique,
        required=True,
    )


def build_pandera_schema(
    yaml_configuration: Optional[Dict[str, Any]],
) -> Optional[pa.DataFrameSchema]:
    """Build a DataFrameSchema from a parsed `<db>.<table>.yaml` dict.

    Returns None when validation is not opted into (no `schema:` block, or no
    column with a `type:` field). Raises ValueError fast on the first unknown
    type or keyword so a task fails at startup, not mid-ingest.
    """
    if not yaml_configuration:
        return None
    columns = yaml_configuration.get("schema") or {}
    typed_columns = {
        name: spec
        for name, spec in columns.items()
        if isinstance(spec, dict) and "type" in spec
    }
    if not typed_columns:
        return None
    return pa.DataFrameSchema(
        {name: _build_column(name, spec) for name, spec in typed_columns.items()},
        strict=False,
        coerce=False,
    )
