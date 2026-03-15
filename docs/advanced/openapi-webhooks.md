# OpenAPI Webhooks

Define application-level webhook event schemas in the OpenAPI specification. Unlike callbacks (which are per-route), webhooks are global event definitions that appear in the top-level `webhooks` section of the OpenAPI spec.

## Overview

Webhooks describe events that your application sends to external systems. For example, a "new user signup" event that fires when a user creates an account. Zigmund lets you define webhooks in the `AppConfig` when initializing the application. These definitions appear in the OpenAPI 3.1 `webhooks` section, allowing API consumers to understand what events your application emits and what payload shape to expect.

This is the Zig equivalent of FastAPI's `webhooks` parameter in the `FastAPI()` constructor.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn webhookInfo(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .message = "This app defines a 'newUser' webhook in the OpenAPI spec",
        .webhook_name = "newUser",
        .description = "Fires when a new user signs up",
    });
}

/// To configure webhooks, pass them in AppConfig when creating the app:
///
///   var app = try zigmund.App.init(allocator, .{
///       .title = "Webhook Demo",
///       .version = "1.0",
///       .webhooks = &.{
///           .{
///               .name = "newUser",
///               .method = .POST,
///               .summary = "New user signup notification",
///               .description = "Sent when a user creates an account",
///               .request_body_schema = .{
///                   .schema_type = "object",
///                   .fields = &.{
///                       .{ .name = "user_id", .schema_type = "string" },
///                       .{ .name = "email", .schema_type = "string", .schema_format = "email" },
///                       .{ .name = "created_at", .schema_type = "string", .schema_format = "date-time" },
///                   },
///               },
///               .response_status = .ok,
///               .response_description = "Webhook received",
///           },
///       },
///   });

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/webhook-info", webhookInfo, .{
        .summary = "OpenAPI webhook definition info",
    });
}
```

## How It Works

### 1. Defining Webhooks in AppConfig

Webhooks are defined at the application level, not on individual routes:

```zig
var app = try zigmund.App.init(allocator, .{
    .title = "My API",
    .version = "1.0",
    .webhooks = &.{
        .{
            .name = "newUser",
            .method = .POST,
            .summary = "New user signup notification",
            .description = "Sent when a user creates an account",
            .request_body_schema = .{
                .schema_type = "object",
                .fields = &.{
                    .{ .name = "user_id", .schema_type = "string" },
                    .{ .name = "email", .schema_type = "string", .schema_format = "email" },
                    .{ .name = "created_at", .schema_type = "string", .schema_format = "date-time" },
                },
            },
            .response_status = .ok,
            .response_description = "Webhook received",
        },
    },
});
```

### 2. Webhook Definition Fields

| Field                  | Type           | Description                                           |
|------------------------|----------------|-------------------------------------------------------|
| `name`                 | `[]const u8`   | Unique name for the webhook event.                    |
| `method`               | enum           | HTTP method used to deliver the webhook (typically `.POST`). |
| `summary`              | `[]const u8`   | Short description of the event.                       |
| `description`          | `[]const u8`   | Detailed description of when and why the event fires. |
| `request_body_schema`  | schema struct  | Schema of the webhook payload.                        |
| `response_status`      | enum           | Expected response status from the webhook receiver.   |
| `response_description` | `[]const u8`   | Description of the expected response.                 |

### 3. Webhooks vs. Callbacks

| Aspect        | Webhooks                          | Callbacks                         |
|---------------|-----------------------------------|-----------------------------------|
| Scope         | Application-level                 | Per-route                         |
| URL source    | Configured externally             | Provided in request body/headers  |
| OpenAPI field | Top-level `webhooks` section      | Per-operation `callbacks` field   |
| Use case      | Global events (user signup, etc.) | Request-specific notifications    |

### 4. OpenAPI 3.1 Spec Output

The webhook definitions appear in the top-level `webhooks` section of the generated OpenAPI JSON:

```json
{
  "webhooks": {
    "newUser": {
      "post": {
        "summary": "New user signup notification",
        "requestBody": {
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "user_id": { "type": "string" },
                  "email": { "type": "string", "format": "email" },
                  "created_at": { "type": "string", "format": "date-time" }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

## Key Points

- Webhooks are application-level event definitions, configured in `AppConfig.webhooks`.
- They document events your API emits, not endpoints your API exposes.
- Webhook definitions are purely for OpenAPI documentation -- Zigmund does not automate webhook delivery.
- Use webhooks for global events; use callbacks for per-request notification URLs.
- The generated OpenAPI spec includes webhooks in the top-level `webhooks` section (OpenAPI 3.1).

## See Also

- [OpenAPI Callbacks](openapi-callbacks.md) -- per-route callback definitions.
- [Path Operation Advanced Configuration](path-operation-advanced-configuration.md) -- other advanced OpenAPI settings.
- [Events](events.md) -- application lifecycle hooks (startup/shutdown).
