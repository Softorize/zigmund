# Path Operation Advanced Configuration

Configure advanced OpenAPI settings on individual routes: response models, deprecation markers, schema visibility, and custom operation identifiers.

## Overview

Beyond `summary` and `tags`, Zigmund's route options support several advanced configuration fields that control how the route appears in the OpenAPI specification. You can specify a typed response model for schema generation, mark routes as deprecated, exclude internal routes from the schema entirely, and assign custom operation IDs.

This is the Zig equivalent of FastAPI's advanced parameters in route decorators (`response_model`, `deprecated`, `include_in_schema`, `operation_id`).

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Demonstrates advanced route configuration options:
/// - include_in_schema: controls OpenAPI visibility
/// - deprecated: marks the route as deprecated in docs
/// - operation_id: custom OpenAPI operation identifier
/// - response_model: typed response schema generation

const ItemResponse = struct {
    name: []const u8,
    price: f64,
    in_stock: bool = true,
};

fn getItem(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .name = "Widget",
        .price = 9.99,
        .in_stock = true,
    });
}

fn deprecatedItem(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .name = "Old Widget",
        .price = 4.99,
        .deprecated = true,
    });
}

fn internalEndpoint(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .message = "This endpoint is hidden from the OpenAPI schema",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Standard route with response_model and custom operation_id
    try app.get("/items", getItem, .{
        .summary = "Advanced route with response model and custom operation ID",
        .operation_id = "get_item_configured",
        .response_model = ItemResponse,
    });

    // Deprecated route — shown in docs with strikethrough
    try app.get("/items/old", deprecatedItem, .{
        .summary = "Deprecated item endpoint",
        .operation_id = "deprecated_item",
        .deprecated = true,
    });

    // Internal route hidden from OpenAPI schema
    try app.get("/internal", internalEndpoint, .{
        .summary = "Internal endpoint excluded from schema",
        .operation_id = "internal_hidden",
        .include_in_schema = false,
    });
}
```

## How It Works

### 1. Response Model

The `response_model` field accepts a Zig struct type. Zigmund generates an OpenAPI schema from the struct's fields at compile time:

```zig
try app.get("/items", getItem, .{
    .response_model = ItemResponse,
});
```

The generated schema includes field names, types, and defaults. This appears in the OpenAPI spec under the route's `200` response.

### 2. Deprecated Routes

Setting `.deprecated = true` marks the route as deprecated in the OpenAPI spec:

```zig
try app.get("/items/old", deprecatedItem, .{
    .deprecated = true,
});
```

Swagger UI displays deprecated routes with a strikethrough and a "Deprecated" label. The route remains functional -- deprecation is purely informational.

### 3. Excluding Routes from the Schema

Setting `.include_in_schema = false` hides the route from the OpenAPI specification entirely:

```zig
try app.get("/internal", internalEndpoint, .{
    .include_in_schema = false,
});
```

The route still works and accepts requests, but it does not appear in Swagger UI, ReDoc, or the OpenAPI JSON. This is useful for internal health checks, debug endpoints, or admin-only routes.

### 4. Custom Operation IDs

The `operation_id` field sets the OpenAPI `operationId`, which is used by code generators to name client methods:

```zig
try app.get("/items", getItem, .{
    .operation_id = "get_item_configured",
});
```

Without an explicit `operation_id`, Zigmund generates one from the handler function name and HTTP method. Custom operation IDs give you full control over generated client code naming.

### 5. Combining Options

All advanced options can be combined:

```zig
try app.get("/items", getItem, .{
    .summary = "Get an item",
    .tags = &.{"items"},
    .operation_id = "get_item",
    .response_model = ItemResponse,
    .status_code = .ok,
    .deprecated = false,
    .include_in_schema = true,
});
```

## Key Points

- `response_model` generates a typed OpenAPI response schema from a Zig struct.
- `deprecated = true` marks a route as deprecated in documentation without removing it.
- `include_in_schema = false` hides a route from the OpenAPI spec entirely.
- `operation_id` controls the identifier used by code generators for client methods.
- All options are compile-time configured -- no runtime overhead.
- These options affect only documentation, not runtime behavior (except `response_model`, which also validates response shape if configured).

## See Also

- [OpenAPI Callbacks](openapi-callbacks.md) -- define callback URLs on routes.
- [OpenAPI Webhooks](openapi-webhooks.md) -- define application-level webhook events.
- [Additional Responses](additional-responses.md) -- document multiple response types.
- [Generate Clients](generate-clients.md) -- generate typed API clients from the OpenAPI spec.
