# OpenAPI Reference

## Overview

Zigmund automatically generates an OpenAPI 3.1 specification from registered routes, parameter markers, security schemes, and route options. This page documents the types used to customize and extend the generated specification.

## OpenApiSchema

Describes a JSON Schema for use in OpenAPI request/response definitions.

```zig
pub const OpenApiSchema = struct {
    schema_type: []const u8 = "string",
    schema_format: ?[]const u8 = null,
    is_array: bool = false,
    fields: []const OpenApiSchemaField = &.{},
    one_of: []const OpenApiSchema = &.{},
    any_of: []const OpenApiSchema = &.{},
    all_of: []const OpenApiSchema = &.{},
    discriminator_property_name: ?[]const u8 = null,
    discriminator_mapping: []const OpenApiDiscriminatorMapping = &.{},
};
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `schema_type` | `[]const u8` | `"string"` | JSON Schema type (string, integer, number, boolean, object, array) |
| `schema_format` | `?[]const u8` | `null` | Format hint (int32, int64, float, double, uri, etc.) |
| `is_array` | `bool` | `false` | Whether this is an array of the schema type |
| `fields` | `[]const OpenApiSchemaField` | `&.{}` | Object properties |
| `one_of` | `[]const OpenApiSchema` | `&.{}` | OneOf composition |
| `any_of` | `[]const OpenApiSchema` | `&.{}` | AnyOf composition |
| `all_of` | `[]const OpenApiSchema` | `&.{}` | AllOf composition |
| `discriminator_property_name` | `?[]const u8` | `null` | Discriminator property for oneOf |
| `discriminator_mapping` | `[]const OpenApiDiscriminatorMapping` | `&.{}` | Discriminator value-to-schema mapping |

## OpenApiSchemaField

Describes a single field within an object schema.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `[]const u8` | (required) | Field name |
| `required` | `bool` | `true` | Whether the field is required |
| `schema_type` | `[]const u8` | `"string"` | Field type |
| `schema_format` | `?[]const u8` | `null` | Format hint |
| `is_array` | `bool` | `false` | Whether the field is an array |
| `fields` | `[]const OpenApiSchemaField` | `&.{}` | Nested object fields |

## OpenApiDiscriminatorMapping

Maps a discriminator value to a schema reference.

| Field | Type | Description |
|-------|------|-------------|
| `value` | `[]const u8` | Discriminator field value |
| `schema_ref` | `[]const u8` | JSON Pointer to the schema |

## ResponseSpec

Declares additional response specifications for a route.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `status_code` | `std.http.Status` | (required) | Response status code |
| `description` | `?[]const u8` | `null` | Response description |
| `content_type` | `?[]const u8` | `null` | Response content type |

## OpenApiExample

Provides named examples for parameters or request/response bodies.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `[]const u8` | (required) | Example name |
| `summary` | `?[]const u8` | `null` | Short summary |
| `description` | `?[]const u8` | `null` | Detailed description |
| `value_json` | `[]const u8` | (required) | JSON-encoded example value |

## OpenApiResponseExamples

Groups examples for a specific response status code.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `status_code` | `std.http.Status` | (required) | Response status code |
| `content_type` | `[]const u8` | `"application/json"` | Content type |
| `examples` | `[]const OpenApiExample` | `&.{}` | Named examples |

## OpenApiExtension

Adds vendor extension fields (x- prefixed) to the specification.

| Field | Type | Description |
|-------|------|-------------|
| `key` | `[]const u8` | Extension key (must start with `x-`) |
| `value_json` | `[]const u8` | JSON-encoded value |

## OpenApiCallback

Defines an OpenAPI callback (webhook triggered by the API).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `[]const u8` | (required) | Callback name |
| `expression` | `[]const u8` | (required) | Runtime expression for the callback URL |
| `method` | `RouteMethod` | `.POST` | HTTP method |
| `operation_id` | `?[]const u8` | `null` | Operation ID |
| `summary` | `?[]const u8` | `null` | Summary |
| `description` | `?[]const u8` | `null` | Description |
| `request_body_required` | `bool` | `true` | Whether request body is required |
| `request_body_content_type` | `[]const u8` | `"application/json"` | Request content type |
| `request_body_schema` | `?OpenApiSchema` | `null` | Request body schema |
| `response_status` | `std.http.Status` | `.ok` | Expected response status |
| `response_description` | `?[]const u8` | `null` | Response description |
| `response_content_type` | `[]const u8` | `"application/json"` | Response content type |
| `response_schema` | `?OpenApiSchema` | `null` | Response schema |
| `tags` | `[]const []const u8` | `&.{}` | Tags |

## OpenApiWebhook

Defines an OpenAPI webhook (external event notification).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `[]const u8` | (required) | Webhook name |
| `method` | `RouteMethod` | `.POST` | HTTP method |
| `operation_id` | `?[]const u8` | `null` | Operation ID |
| `summary` | `?[]const u8` | `null` | Summary |
| `description` | `?[]const u8` | `null` | Description |
| `request_body_required` | `bool` | `true` | Whether request body is required |
| `request_body_content_type` | `[]const u8` | `"application/json"` | Content type |
| `request_body_schema` | `?OpenApiSchema` | `null` | Request body schema |
| `response_status` | `std.http.Status` | `.ok` | Expected response status |
| `response_description` | `?[]const u8` | `null` | Response description |
| `response_content_type` | `[]const u8` | `"application/json"` | Response content type |
| `response_schema` | `?OpenApiSchema` | `null` | Response schema |
| `tags` | `[]const []const u8` | `&.{}` | Tags |

## OpenApiSecurityRequirement

Specifies a security scheme and its required scopes.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `scheme` | `[]const u8` | (required) | Security scheme name |
| `scopes` | `[]const []const u8` | `&.{}` | Required scopes |

## OpenApiSecurityAlternative

Groups security requirements as alternatives (logical OR).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `requirements` | `[]const OpenApiSecurityRequirement` | `&.{}` | Alternative security requirements |

## Accessing the Generated Spec

```zig
const spec_json = try app.openapi();
```

The result is cached and invalidated automatically when routes or security schemes change.

## Example

```zig
try app.post("/items", createItem, .{
    .summary = "Create an item",
    .response_model = ItemResponse,
    .status_code = .created,
    .responses = &.{
        .{ .status_code = .conflict, .description = "Item already exists" },
    },
    .openapi_request_examples = &.{
        .{
            .name = "basic",
            .summary = "Basic item",
            .value_json = "{\"name\":\"Widget\",\"price\":9.99}",
        },
    },
    .openapi_callbacks = &.{
        .{
            .name = "onItemCreated",
            .expression = "{$request.body#/callback_url}",
            .summary = "Notify when item is created",
        },
    },
});
```
