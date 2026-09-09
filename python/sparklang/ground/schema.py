"""Minimal JSON Schema subset — no xgrammar / heavy deps.

Supports: type, required, properties, enum, const, minLength,
maxLength, minimum, maximum, items (single schema). Used to
verify structured model output before speak.
"""

from __future__ import annotations

from typing import Any, Optional


def validate_json_schema(
    instance: Any,
    schema: dict[str, Any],
) -> tuple[bool, Optional[str]]:
    """Return (ok, error). Fail closed on unsupported keywords."""
    if not isinstance(schema, dict):
        return False, "schema must be object"
    t = schema.get("type")
    if t is not None:
        ok, err = _check_type(instance, t)
        if not ok:
            return False, err
    if "const" in schema and instance != schema["const"]:
        return False, f"const mismatch want {schema['const']!r}"
    if "enum" in schema:
        if instance not in schema["enum"]:
            return False, "enum miss"
    if isinstance(instance, str):
        mn = schema.get("minLength")
        mx = schema.get("maxLength")
        if mn is not None and len(instance) < int(mn):
            return False, "minLength"
        if mx is not None and len(instance) > int(mx):
            return False, "maxLength"
    if isinstance(instance, (int, float)) and not isinstance(
        instance, bool
    ):
        mn = schema.get("minimum")
        mx = schema.get("maximum")
        if mn is not None and instance < mn:
            return False, "minimum"
        if mx is not None and instance > mx:
            return False, "maximum"
    if isinstance(instance, dict):
        req = schema.get("required") or []
        for key in req:
            if key not in instance:
                return False, f"required missing {key!r}"
        props = schema.get("properties") or {}
        for key, sub in props.items():
            if key in instance:
                ok, err = validate_json_schema(instance[key], sub)
                if not ok:
                    return False, f"{key}: {err}"
    if isinstance(instance, list) and "items" in schema:
        item_schema = schema["items"]
        if not isinstance(item_schema, dict):
            return False, "items must be object schema"
        for i, el in enumerate(instance):
            ok, err = validate_json_schema(el, item_schema)
            if not ok:
                return False, f"items[{i}]: {err}"
    return True, None


def _check_type(instance: Any, t: Any) -> tuple[bool, Optional[str]]:
    """Map JSON Schema type names to Python types."""
    mapping = {
        "object": dict,
        "array": list,
        "string": str,
        "integer": int,
        "number": (int, float),
        "boolean": bool,
        "null": type(None),
    }
    if isinstance(t, list):
        for alt in t:
            ok, _ = _check_type(instance, alt)
            if ok:
                return True, None
        return False, f"type miss want one of {t}"
    py = mapping.get(str(t))
    if py is None:
        return False, f"unsupported type {t!r}"
    if t == "integer" and isinstance(instance, bool):
        return False, "type miss integer"
    if t == "number" and isinstance(instance, bool):
        return False, "type miss number"
    if not isinstance(instance, py):
        return False, f"type miss want {t}"
    return True, None
