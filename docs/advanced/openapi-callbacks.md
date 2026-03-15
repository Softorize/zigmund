# OpenAPI Callbacks

Define callback URLs in your OpenAPI specification to document out-of-band HTTP requests your API makes to caller-provided endpoints, such as webhook-style notifications.

## Overview

Callbacks are API-initiated requests to a URL provided by the caller. For example, when creating an invoice, the caller provides a `callback_url`, and the API sends a POST to that URL when the invoice is paid. Zigmund lets you document these callbacks in the OpenAPI spec via the `openapi_callbacks` field in route options.

This is the Zig equivalent of FastAPI's `callbacks` parameter in route decorators.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Demonstrates OpenAPI callback definitions. Callbacks describe
/// out-of-band HTTP requests the API will make to a caller-provided URL,
/// such as webhook-style notifications after an invoice is created.

fn createInvoice(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var response = try zigmund.Response.json(allocator, .{
        .invoice_id = "inv-001",
        .status = "pending",
        .message = "Invoice created; callback will fire when paid",
    });
    return response.withStatus(.created);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/invoices", createInvoice, .{
        .summary = "Create invoice with payment callback notification",
        .openapi_callbacks = &.{
            .{
                .name = "invoicePaid",
                .expression = "{$request.body#/callback_url}",
                .method = .POST,
                .operation_id = "invoice_paid_callback",
                .summary = "Notification sent when invoice is paid",
                .description = "The API sends a POST to the callback URL with payment details",
                .request_body_schema = .{
                    .schema_type = "object",
                    .fields = &.{
                        .{ .name = "invoice_id", .schema_type = "string" },
                        .{ .name = "paid_at", .schema_type = "string", .schema_format = "date-time" },
                        .{ .name = "amount", .schema_type = "number" },
                    },
                },
                .response_status = .ok,
                .response_description = "Callback acknowledged",
            },
        },
    });
}
```

## How It Works

### 1. Callback Definition Structure

Each callback is defined as a struct within the `openapi_callbacks` slice:

| Field                  | Type           | Description                                              |
|------------------------|----------------|----------------------------------------------------------|
| `name`                 | `[]const u8`   | Identifier for the callback in the OpenAPI spec.         |
| `expression`           | `[]const u8`   | Runtime expression resolving to the callback URL.        |
| `method`               | enum           | HTTP method for the callback request (`.POST`, etc.).    |
| `operation_id`         | `[]const u8`   | OpenAPI operation ID for the callback.                   |
| `summary`              | `[]const u8`   | Short description of the callback.                       |
| `description`          | `[]const u8`   | Detailed description.                                    |
| `request_body_schema`  | schema struct  | Schema of the callback request body.                     |
| `response_status`      | enum           | Expected response status from the callback receiver.     |
| `response_description` | `[]const u8`   | Description of the expected callback response.           |

### 2. Runtime Expressions

The `expression` field uses OpenAPI runtime expression syntax to reference values from the original request:

```
{$request.body#/callback_url}
```

This means: "The callback URL is in the `callback_url` field of the request body." Other examples:

- `{$request.query.callback}` -- from a query parameter.
- `{$request.header.X-Callback-URL}` -- from a request header.

### 3. Callback Request Body Schema

Define the schema of the data your API sends to the callback URL:

```zig
.request_body_schema = .{
    .schema_type = "object",
    .fields = &.{
        .{ .name = "invoice_id", .schema_type = "string" },
        .{ .name = "paid_at", .schema_type = "string", .schema_format = "date-time" },
        .{ .name = "amount", .schema_type = "number" },
    },
},
```

This generates the corresponding JSON Schema in the OpenAPI spec, so API consumers know exactly what payload to expect.

### 4. How It Appears in the OpenAPI Spec

The callback definition appears in the `callbacks` section of the path operation in the generated OpenAPI JSON. Tools like Swagger UI display callbacks alongside the route's primary request/response documentation.

## Key Points

- Callbacks document out-of-band HTTP requests your API makes to caller-provided URLs.
- They are purely documentation -- Zigmund does not enforce or automate the actual callback request.
- The `expression` field uses OpenAPI runtime expressions to specify where the callback URL comes from.
- Define the callback request body schema so consumers know what data your API will send.
- Callbacks appear in the OpenAPI spec and are rendered by Swagger UI and ReDoc.

## See Also

- [OpenAPI Webhooks](openapi-webhooks.md) -- application-level webhook definitions (not per-route).
- [Path Operation Advanced Configuration](path-operation-advanced-configuration.md) -- other advanced route options.
- [Additional Responses](additional-responses.md) -- document alternative response shapes.
