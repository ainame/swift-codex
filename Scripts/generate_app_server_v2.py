#!/usr/bin/env python3
from __future__ import annotations

import json
import keyword
import re
from copy import deepcopy
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = REPO_ROOT / "vendor" / "openai-codex" / "sdk" / "python" / "src" / "codex_app_server" / "generated" / "notification_registry.py"
SCHEMA_PATH = REPO_ROOT / "vendor" / "openai-codex" / "codex-rs" / "app-server-protocol" / "schema" / "json" / "codex_app_server_protocol.v2.schemas.json"
OUTPUT_DIR = REPO_ROOT / "Sources" / "Codex" / "RPCModels" / "Generated"

SWIFT_RESERVED = {
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
    "import", "init", "inout", "internal", "let", "open", "operator", "private",
    "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias",
    "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
    "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as",
    "Any", "catch", "false", "is", "nil", "super", "self", "Self", "throw", "throws",
    "true", "try",
}

ROOT_TYPES = {
    "ApprovalsReviewer",
    "AskForApproval",
    "ClientInfo",
    "InitializeResponse",
    "Model",
    "ModelListResponse",
    "PluginListResponse",
    "Personality",
    "ReasoningEffort",
    "ReasoningSummary",
    "SandboxMode",
    "SandboxPolicy",
    "ServerInfo",
    "ServiceTier",
    "SortDirection",
    "Thread",
    "ThreadArchiveResponse",
    "ThreadCompactStartResponse",
    "ThreadForkResponse",
    "ThreadItem",
    "ThreadListResponse",
    "ThreadReadResponse",
    "ThreadResumeResponse",
    "ThreadSetNameResponse",
    "ThreadSortKey",
    "ThreadSourceKind",
    "ThreadStartSource",
    "ThreadStartResponse",
    "ThreadStatus",
    "ThreadTokenUsage",
    "ThreadUnarchiveResponse",
    "Turn",
    "TurnError",
    "TurnInterruptResponse",
    "TurnPlanStep",
    "TurnPlanStepStatus",
    "TurnStartResponse",
    "TurnStatus",
    "TurnSteerResponse",
    "TokenUsageBreakdown",
}

MANUAL_DEFINITIONS = {
    "ServerInfo": {
        "type": "object",
        "properties": {
            "name": {"type": ["string", "null"]},
            "version": {"type": ["string", "null"]},
        },
    },
    "InitializeResponse": {
        "type": "object",
        "properties": {
            "serverInfo": {"anyOf": [{"$ref": "#/definitions/ServerInfo"}, {"type": "null"}]},
            "userAgent": {"type": ["string", "null"]},
            "platformFamily": {"type": ["string", "null"]},
            "platformOs": {"type": ["string", "null"]},
        },
    },
}

COMPATIBILITY_DEFAULTS = {
    ("Thread", "ephemeral"): "false",
    ("Thread", "status"): '.idle(IdleThreadStatus(type: .idle))',
    ("ThreadStartResponse", "approvalsReviewer"): ".user",
    ("ThreadResumeResponse", "approvalsReviewer"): ".user",
    ("ThreadForkResponse", "approvalsReviewer"): ".user",
}


def read_notification_registry() -> list[tuple[str, str]]:
    text = REGISTRY_PATH.read_text()
    return re.findall(r'"([^"]+)": (\w+),', text)


def upper_camel(value: str) -> str:
    parts = re.split(r"[^A-Za-z0-9]+", value)
    return "".join(part[:1].upper() + part[1:] for part in parts if part)


def lower_camel(value: str) -> str:
    upper = upper_camel(value)
    if not upper:
        return "value"
    return upper[:1].lower() + upper[1:]


def sanitize_type_name(value: str) -> str:
    value = upper_camel(value)
    if not value:
        value = "GeneratedType"
    if value[:1].isdigit():
        value = f"Value{value}"
    if value in SWIFT_RESERVED:
        value += "Value"
    return value


def sanitize_property_name(value: str) -> str:
    name = lower_camel(value)
    if not name:
        name = "value"
    if keyword.iskeyword(name) or name in SWIFT_RESERVED:
        name = f"{name}Value"
    if name[:1].isdigit():
        name = f"value{name}"
    return name


def sanitize_case_name(value: str) -> str:
    name = lower_camel(value)
    if not name:
        name = "value"
    if name in SWIFT_RESERVED:
        name += "Value"
    return name


def json_string(value: str) -> str:
    return json.dumps(value)


def optional_of(swift_type: str) -> str:
    return swift_type if swift_type.endswith("?") else f"{swift_type}?"


def base_type(swift_type: str) -> str:
    return swift_type[:-1] if swift_type.endswith("?") else swift_type


def non_null_variants(schema: dict) -> list[dict] | None:
    for key in ("anyOf", "oneOf"):
        variants = schema.get(key)
        if not variants:
            continue
        non_null = [variant for variant in variants if variant.get("type") != "null"]
        if len(non_null) == 1 and len(variants) == 2:
            return non_null
    type_field = schema.get("type")
    if isinstance(type_field, list) and "null" in type_field:
        non_null_types = [value for value in type_field if value != "null"]
        if len(non_null_types) == 1:
            copy = deepcopy(schema)
            copy["type"] = non_null_types[0]
            return [copy]
    return None


class Registry:
    def __init__(self, definitions: dict[str, dict]) -> None:
        self.definitions = deepcopy(definitions)
        self.ordered_names: list[str] = []
        self._seen: set[str] = set()

    def include(self, name: str) -> None:
        if name not in self.definitions:
            return
        if name not in self._seen:
            self._seen.add(name)
            self.ordered_names.append(name)
        self._scan_schema(name, self.definitions[name])

    def add_inline(self, suggested_name: str, schema: dict) -> str:
        base_name = sanitize_type_name(schema.get("title") or suggested_name)
        name = base_name
        index = 2
        while name in self.definitions:
            name = f"{base_name}{index}"
            index += 1
        self.definitions[name] = deepcopy(schema)
        self.include(name)
        return name

    def _scan_schema(self, owner_name: str, schema: dict) -> None:
        if isinstance(schema, bool):
            return
        if "$ref" in schema:
            self.include(ref_name(schema["$ref"]))
            return
        for key in ("anyOf", "allOf", "oneOf"):
            for variant in schema.get(key, []):
                self._scan_schema(owner_name, variant)
        type_field = schema.get("type")
        if isinstance(type_field, list):
            for item in type_field:
                if item != "null":
                    self._scan_schema(owner_name, {**schema, "type": item})
            return
        if type_field == "array" and "items" in schema:
            self._scan_schema(owner_name, schema["items"])
            return
        if type_field == "object" or "properties" in schema or "additionalProperties" in schema:
            for property_name, property_schema in schema.get("properties", {}).items():
                self._scan_schema(f"{owner_name}{sanitize_type_name(property_name)}", property_schema)
            additional = schema.get("additionalProperties")
            if isinstance(additional, dict):
                self._scan_schema(f"{owner_name}Entry", additional)


def ref_name(ref: str) -> str:
    return ref.rsplit("/", 1)[-1]


def schema_kind(schema: dict) -> str:
    if "enum" in schema:
        return "enum"
    if "oneOf" in schema or ("anyOf" in schema and non_null_variants(schema) is None):
        return "union"
    type_field = schema.get("type")
    if isinstance(type_field, list):
        non_null = [value for value in type_field if value != "null"]
        type_field = non_null[0] if len(non_null) == 1 else None
    if type_field == "object" or "properties" in schema or "additionalProperties" in schema:
        return "object"
    if type_field in {"string", "integer", "number", "boolean"}:
        return "scalar"
    if "allOf" in schema:
        refs = [variant["$ref"] for variant in schema["allOf"] if "$ref" in variant]
        if len(refs) == 1:
            return "alias"
    return "scalar"


def swift_type(registry: Registry, schema: dict, context_name: str) -> str:
    if isinstance(schema, bool):
        return "JSONValue"
    if "$ref" in schema:
        return ref_name(schema["$ref"])

    optional_variant = non_null_variants(schema)
    if optional_variant is not None:
        return optional_of(swift_type(registry, optional_variant[0], context_name))

    if "allOf" in schema and len(schema["allOf"]) == 1:
        return swift_type(registry, schema["allOf"][0], context_name)

    if "enum" in schema:
        return registry.add_inline(context_name, schema)

    if "oneOf" in schema or "anyOf" in schema:
        return registry.add_inline(context_name, schema)

    type_field = schema.get("type")
    if type_field == "string":
        return "String"
    if type_field == "integer":
        return "Int"
    if type_field == "number":
        return "Double"
    if type_field == "boolean":
        return "Bool"
    if type_field == "array":
        return f"[{swift_type(registry, schema.get('items', {}), context_name + 'Item')}]"
    if type_field == "object" or "properties" in schema:
        if schema.get("properties"):
            return registry.add_inline(context_name, schema)
        additional = schema.get("additionalProperties")
        if additional is True:
            return "JSONObject"
        if isinstance(additional, dict):
            return f"[String: {swift_type(registry, additional, context_name + 'Entry')}]"
        return "JSONObject"
    return "JSONValue"


def render_coding_keys(coding_pairs: list[tuple[str, str]]) -> str:
    entries = []
    for property_name, json_name in coding_pairs:
        if property_name == json_name:
            entries.append(f"            case {property_name}")
        else:
            entries.append(f'            case {property_name} = {json_string(json_name)}')
    return "\n".join(entries)


def render_object(name: str, schema: dict, registry: Registry) -> str:
    properties = schema.get("properties", {})
    required = set(schema.get("required", []))
    coding_pairs: list[tuple[str, str]] = []
    fields: list[tuple[str, str, str, bool]] = []

    for json_name, property_schema in properties.items():
        property_name = sanitize_property_name(json_name)
        property_type = swift_type(registry, property_schema, f"{name}{sanitize_type_name(json_name)}")
        is_required = json_name in required and not property_type.endswith("?")
        if not is_required:
            property_type = optional_of(property_type)
        coding_pairs.append((property_name, json_name))
        fields.append((property_name, json_name, property_type, is_required))

    payload_fields = "\n".join(
        f"        var {property_name}: {property_type}"
        for property_name, _, property_type, _ in fields
    )
    public_fields = "\n".join(
        f"    public var {property_name}: {property_type}"
        for property_name, _, property_type, _ in fields
    )
    init_params = ",\n".join(
        f"        {property_name}: {property_type}{'' if is_required else ' = nil'}"
        for property_name, _, property_type, is_required in fields
    )
    init_assignments = "\n".join(
        f"        self.{property_name} = {property_name}"
        for property_name, _, _, _ in fields
    )
    payload_assignment = ",\n".join(
        f"            {property_name}: {property_name}"
        for property_name, _, _, _ in fields
    )
    decode_assignments = "\n".join(
        f"        self.{property_name} = payload.{property_name}"
        for property_name, _, _, _ in fields
    )
    known_keys = ", ".join(json_string(json_name) for _, json_name, _, _ in fields)
    coding_keys = render_coding_keys(coding_pairs)
    payload_properties = payload_fields if payload_fields else ""
    if fields:
        initializer_signature = f"{init_params},\n        additionalFields: JSONObject = [:]"
        payload_initializer = f"        Payload(\n{payload_assignment}\n        )"
        decode_payload = "        let payload = try decodeJSONValue(Payload.self, from: .object(object))"
        payload_decoder = ""
        payload_decoder_block = ""
        if any((name, json_name) in COMPATIBILITY_DEFAULTS for _, json_name, _, _ in fields):
            payload_init_params = ",\n".join(
                f"            {property_name}: {property_type}"
                for property_name, _, property_type, _ in fields
            )
            payload_init_assignments = "\n".join(
                f"            self.{property_name} = {property_name}"
                for property_name, _, _, _ in fields
            )
            decode_lines: list[str] = []
            for property_name, json_name, property_type, is_required in fields:
                field_base_type = base_type(property_type)
                compatibility_default = COMPATIBILITY_DEFAULTS.get((name, json_name))
                if compatibility_default is not None:
                    decode_lines.append(
                        f"            self.{property_name} = try container.decodeIfPresent({field_base_type}.self, forKey: .{property_name}) ?? {compatibility_default}"
                    )
                elif is_required:
                    decode_lines.append(
                        f"            self.{property_name} = try container.decode({field_base_type}.self, forKey: .{property_name})"
                    )
                else:
                    decode_lines.append(
                        f"            self.{property_name} = try container.decodeIfPresent({field_base_type}.self, forKey: .{property_name})"
                    )
            payload_decoder = """

        init(
{payload_init_params}
        ) {
{payload_init_assignments}
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
{decode_lines}
        }""".replace("{payload_init_params}", payload_init_params).replace("{payload_init_assignments}", payload_init_assignments).replace("{decode_lines}", "\n".join(decode_lines))
            payload_decoder_block = f"\n{payload_decoder}" if payload_decoder else ""
        payload_struct = f"""    private struct Payload: Codable, Hashable, Sendable {{
{payload_properties}

        enum CodingKeys: String, CodingKey {{
{coding_keys}
        }}{payload_decoder_block}
    }}"""
    else:
        initializer_signature = "        additionalFields: JSONObject = [:]"
        payload_initializer = "        Payload()"
        decode_payload = "        _ = try decodeJSONValue(Payload.self, from: .object(object))"
        payload_struct = "    private struct Payload: Codable, Hashable, Sendable {}"

    return f"""public struct {name}: ObjectModel {{
{public_fields if public_fields else ""}
    public var additionalFields: JSONObject

    public init(
{initializer_signature}
    ) {{
{init_assignments if init_assignments else ""}
        self.additionalFields = additionalFields
    }}

    public var rawJSON: JSONValue {{
        .object(mergedJSONObject(payload, additionalFields: additionalFields, context: {json_string(name)}))
    }}

    public init(from decoder: any Decoder) throws {{
        let object = try decodeJSONObject(from: decoder, context: {json_string(name)})
{decode_payload}
{decode_assignments if decode_assignments else ""}
        self.additionalFields = object.filter {{ !Self.knownKeys.contains($0.key) }}
    }}

    public func encode(to encoder: any Encoder) throws {{
        try encodeJSONObject(payload, additionalFields: additionalFields, context: {json_string(name)}, to: encoder)
    }}

    private var payload: Payload {{
{payload_initializer}
    }}

    private static let knownKeys: Set<String> = [{known_keys}]

{payload_struct}
}}
"""


def enum_case(value: str) -> str:
    if value == "":
        return "empty"
    if re.fullmatch(r"[A-Za-z0-9_]+", value):
        name = sanitize_case_name(value)
    else:
        name = sanitize_case_name(re.sub(r"[^A-Za-z0-9]+", "_", value))
    return name


def union_string_case(value: str) -> str:
    name = enum_case(value)
    return "unknownValue" if name == "unknown" else name


def render_enum(name: str, schema: dict) -> str:
    values = schema["enum"]
    cases = "\n".join(f"    case {enum_case(str(value))}" for value in values)
    init_cases = "\n".join(
        f"        case {json_string(str(value))}: self = .{enum_case(str(value))}"
        for value in values
    )
    raw_cases = "\n".join(
        f"        case .{enum_case(str(value))}: return {json_string(str(value))}"
        for value in values
    )
    return f"""public enum {name}: RawJSONRepresentable {{
{cases}
    case unrecognized(String)

    public init(from decoder: any Decoder) throws {{
        let value = try String(from: decoder)
        switch value {{
{init_cases}
        default:
            self = .unrecognized(value)
        }}
    }}

    public func encode(to encoder: any Encoder) throws {{
        try rawValue.encode(to: encoder)
    }}

    public var rawValue: String {{
        switch self {{
{raw_cases}
        case .unrecognized(let value):
            return value
        }}
    }}

    public var rawJSON: JSONValue {{
        .string(rawValue)
    }}
}}
"""


def discriminator_info(schema: dict, parent_name: str, registry: Registry, index: int) -> tuple[str, str, str] | None:
    if isinstance(schema, bool):
        return None
    if "$ref" in schema:
        ref = ref_name(schema["$ref"])
        target_schema = registry.definitions[ref]
        info = discriminator_info(target_schema, parent_name, registry, index)
        if info is None:
            return None
        key, literal, _ = info
        return key, literal, ref

    properties = schema.get("properties", {})
    for key, property_schema in properties.items():
        if not isinstance(property_schema, dict):
            continue
        enum_values = property_schema.get("enum")
        if isinstance(enum_values, list) and len(enum_values) == 1 and isinstance(enum_values[0], str):
            variant_name = schema.get("title") or f"{parent_name}Variant{index}"
            type_name = registry.add_inline(variant_name, schema)
            return key, enum_values[0], type_name
    return None


def union_case_name(parent_name: str, variant_name: str, fallback: str) -> str:
    simplified = variant_name
    for suffix in (parent_name, "Notification", "ThreadItem", "ThreadStatus", "SandboxPolicy"):
        if simplified.endswith(suffix) and simplified != suffix:
            simplified = simplified[: -len(suffix)]
            break
    simplified = simplified or fallback
    case_name = sanitize_case_name(simplified)
    if case_name == "unknown":
        return "unknownValue"
    return case_name


def render_union(name: str, schema: dict, registry: Registry) -> str:
    variants = schema.get("oneOf") or schema.get("anyOf") or []
    string_literals: list[str] = []
    associated_cases: list[tuple[str, str]] = []
    object_dispatch: list[tuple[str, str, str]] = []
    decode_attempts: list[str] = []

    for index, variant in enumerate(variants, start=1):
        if variant.get("type") == "null":
            continue
        if variant.get("type") == "string" and "enum" in variant:
            string_literals.extend(str(value) for value in variant["enum"])
            continue

        type_name = swift_type(registry, variant, f"{name}Variant{index}")
        raw_variant_name = type_name
        case_name = union_case_name(name, raw_variant_name, f"variant{index}")
        associated_cases.append((case_name, type_name))
        discriminant = discriminator_info(variant, name, registry, index)
        if discriminant is not None:
            object_dispatch.append((discriminant[0], discriminant[1], case_name))
        decode_attempts.append(
            f"        if let value = try? decodeJSONValue({type_name}.self, from: raw) {{ self = .{case_name}(value); return }}"
        )

    string_cases = "\n".join(f"    case {union_string_case(value)}" for value in string_literals)
    string_init_cases = "\n".join(
        f"            case {json_string(value)}: self = .{union_string_case(value)}; return"
        for value in string_literals
    )
    associated_case_lines = "\n".join(
        f"    case {case_name}({type_name})"
        for case_name, type_name in associated_cases
    )
    dispatch_blocks = "\n".join(
        f"            case {json_string(literal)}:\n                if let value = try? decodeJSONValue({next(type_name for case_name2, type_name in associated_cases if case_name2 == case_name)}.self, from: raw) {{\n                    self = .{case_name}(value)\n                    return\n                }}"
        for key, literal, case_name in object_dispatch
    )
    raw_cases = "\n".join(
        f"        case .{case_name}(let value): return losslessEncodeJSONValue(value, context: {json_string(name + '.' + case_name)})"
        for case_name, _ in associated_cases
    )
    string_raw_cases = "\n".join(
        f"        case .{union_string_case(value)}: return .string({json_string(value)})"
        for value in string_literals
    )
    encode_cases = "\n".join(
        f"        case .{case_name}(let value): try value.encode(to: encoder)"
        for case_name, _ in associated_cases
    )
    encode_string_cases = "\n".join(
        f"        case .{union_string_case(value)}: try {json_string(value)}.encode(to: encoder)"
        for value in string_literals
    )

    object_switch = ""
    if object_dispatch:
        first_key = object_dispatch[0][0]
        all_same_key = all(key == first_key for key, _, _ in object_dispatch)
        if all_same_key:
            object_switch = f"""        if case .object(let object) = raw, let discriminator = object[{json_string(first_key)}]?.stringValue {{
            switch discriminator {{
{dispatch_blocks}
            default:
                break
            }}
        }}
"""

    return f"""public enum {name}: RawJSONRepresentable {{
{string_cases if string_cases else ""}
{associated_case_lines if associated_case_lines else ""}
    case unknown(JSONValue)

    public init(from decoder: any Decoder) throws {{
        let raw = try JSONValue(from: decoder)
        if case .string(let value) = raw {{
            switch value {{
{string_init_cases if string_init_cases else ""}
            default:
                break
            }}
        }}
{object_switch if object_switch else ""}{''.join(line + chr(10) for line in decode_attempts)}        self = .unknown(raw)
    }}

    public func encode(to encoder: any Encoder) throws {{
        switch self {{
{encode_string_cases if encode_string_cases else ""}
{encode_cases if encode_cases else ""}
        case .unknown(let value):
            try value.encode(to: encoder)
        }}
    }}

    public var rawJSON: JSONValue {{
        switch self {{
{string_raw_cases if string_raw_cases else ""}
{raw_cases if raw_cases else ""}
        case .unknown(let value):
            return value
        }}
    }}
}}
"""


def render_scalar(name: str, schema: dict) -> str:
    type_field = schema.get("type")
    if isinstance(type_field, list):
        type_field = next((value for value in type_field if value != "null"), "string")
    swift_scalar = {
        "string": "String",
        "integer": "Int",
        "number": "Double",
        "boolean": "Bool",
    }.get(type_field, "String")
    value_accessor = {
        "String": "stringValue",
        "Int": "intValue",
        "Double": "doubleValue",
        "Bool": "boolValue",
    }[swift_scalar]
    default_json = {
        "String": "JSONValue.string(rawValue)",
        "Int": "JSONValue.number(Double(rawValue))",
        "Double": "JSONValue.number(rawValue)",
        "Bool": "JSONValue.bool(rawValue)",
    }[swift_scalar]
    return f"""public struct {name}: RawRepresentable, RawJSONRepresentable {{
    public var rawValue: {swift_scalar}

    public init(rawValue: {swift_scalar}) {{
        self.rawValue = rawValue
    }}

    public init(from decoder: any Decoder) throws {{
        let raw = try JSONValue(from: decoder)
        guard let value = raw.{value_accessor} else {{
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: {json_string(name + " must decode from a " + swift_scalar)})
            )
        }}
        self.rawValue = value
    }}

    public func encode(to encoder: any Encoder) throws {{
        switch rawJSON {{
        case .string(let value):
            try value.encode(to: encoder)
        case .number(let value):
            try value.encode(to: encoder)
        case .bool(let value):
            try value.encode(to: encoder)
        default:
            try rawJSON.encode(to: encoder)
        }}
    }}

    public var rawJSON: JSONValue {{
        {default_json}
    }}
}}
"""


def render_alias(name: str, schema: dict) -> str:
    target = swift_type(REGISTRY, schema["allOf"][0], f"{name}Value")
    return f"public typealias {name} = {target}\n"


def emit_definition(name: str, schema: dict, registry: Registry) -> str:
    kind = schema_kind(schema)
    if kind == "enum":
        return render_enum(name, schema)
    if kind == "union":
        return render_union(name, schema, registry)
    if kind == "object":
        return render_object(name, schema, registry)
    if kind == "alias":
        return render_alias(name, schema)
    return render_scalar(name, schema)


def emit_notification_payload(mapping: list[tuple[str, str]]) -> str:
    cases: list[str] = []
    init_cases: list[str] = []
    raw_cases: list[str] = []
    metadata_thread_cases: list[str] = []
    metadata_turn_cases: list[str] = []

    for method, type_name in mapping:
        if type_name not in REGISTRY.definitions:
            continue
        case_name = sanitize_case_name(type_name[:-12] if type_name.endswith("Notification") else type_name)
        cases.append(f"    case {case_name}({type_name})")
        init_cases.append(f'        case {json_string(method)}: self = .{case_name}(try decodeJSONValue({type_name}.self, from: params))')
        raw_cases.append(f"        case .{case_name}(let value): return value.rawJSON")

        schema = REGISTRY.definitions[type_name]
        properties = schema.get("properties", {})
        if "threadId" in properties:
            metadata_thread_cases.append(f"        case .{case_name}(let value): return value.threadId")
        elif type_name == "ThreadStartedNotification":
            metadata_thread_cases.append(f"        case .{case_name}(let value): return value.thread.id")

        if "turnId" in properties:
            metadata_turn_cases.append(f"        case .{case_name}(let value): return value.turnId")
        elif type_name in {"TurnStartedNotification", "TurnCompletedNotification"}:
            metadata_turn_cases.append(f"        case .{case_name}(let value): return value.turn.id")

    return f"""public enum CodexNotificationPayload: RawJSONRepresentable {{
{chr(10).join(cases)}
    case unknown(method: String, rawJSON: JSONValue)

    init(method: String, params: JSONValue) throws {{
        switch method {{
{chr(10).join(init_cases)}
        default:
            self = .unknown(method: method, rawJSON: params)
        }}
    }}

    public var rawJSON: JSONValue {{
        switch self {{
{chr(10).join(raw_cases)}
        case .unknown(_, let rawJSON):
            return rawJSON
        }}
    }}

    var threadID: String? {{
        switch self {{
{chr(10).join(metadata_thread_cases)}
        case .unknown(_, let rawJSON):
            if let direct = rawJSON.objectValue?.stringValue(forKey: "threadId") {{
                return direct
            }}
            return rawJSON.objectValue?["thread"]?.objectValue?.stringValue(forKey: "id")
        default:
            return nil
        }}
    }}

    var turnID: String? {{
        switch self {{
{chr(10).join(metadata_turn_cases)}
        case .unknown(_, let rawJSON):
            if let direct = rawJSON.objectValue?.stringValue(forKey: "turnId") {{
                return direct
            }}
            return rawJSON.objectValue?["turn"]?.objectValue?.stringValue(forKey: "id")
        default:
            return nil
        }}
    }}
}}
"""


def generated_file_content(body: str) -> str:
    return f"""// Generated by Scripts/generate_app_server_v2.py.
// Do not edit manually.

import Foundation

{body}
"""


def main() -> None:
    global REGISTRY
    schema = json.loads(SCHEMA_PATH.read_text())
    definitions = schema.get("definitions", {})
    definitions.update(MANUAL_DEFINITIONS)
    REGISTRY = Registry(definitions)

    mapping = read_notification_registry()
    for root in sorted(ROOT_TYPES):
        REGISTRY.include(root)
    for _, type_name in mapping:
        REGISTRY.include(type_name)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for path in OUTPUT_DIR.glob("*.swift"):
        path.unlink()

    for name in REGISTRY.ordered_names:
        body = emit_definition(name, REGISTRY.definitions[name], REGISTRY)
        (OUTPUT_DIR / f"{name}.swift").write_text(generated_file_content(body))

    notification_payload = emit_notification_payload(mapping)
    (OUTPUT_DIR / "CodexNotificationPayload.swift").write_text(generated_file_content(notification_payload))


if __name__ == "__main__":
    main()
