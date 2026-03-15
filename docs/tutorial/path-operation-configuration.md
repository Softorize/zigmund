# Path Operation Configuration

Configure route-level metadata -- summaries, descriptions, tags, operation IDs, and additional response definitions -- to produce rich, well-organized OpenAPI documentation.

## Overview

Every route registered with Zigmund accepts a configuration struct as its third argument. This struct controls how the route appears in generated documentation and how the framework handles certain operational details. While `.summary` and `.tags` are the most commonly used fields, the full set of options lets you describe your API contract precisely enough for code generators, testing tools, and API gateways to consume.

Key configuration fields:

| Field           | Type                | Purpose                                                    |
|-----------------|---------------------|------------------------------------------------------------|
| `name`          | `[]const u8`        | Internal route name (used for URL reversal).               |
| `summary`       | `[]const u8`        | Short one-line description shown in docs.                  |
| `description`   | `[]const u8`        | Long-form Markdown description for detailed docs.          |
| `tags`          | `[]const []const u8`| Groups the route under named sections in Swagger UI.       |
| `operation_id`  | `[]const u8`        | Unique identifier for the operation in the OpenAPI schema. |
| `responses`     | response list       | Additional response status codes and descriptions.         |

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn readConfiguredOperation(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .operation = "configured",
        .ok = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/path-operation-configuration/items", readConfiguredOperation, .{
        .name = "configured_operation",
        .summary = "Configured path operation",
        .description = "Demonstrates route metadata fields used for docs and OpenAPI generation.",
        .tags = &.{ "parity", "tutorial", "configuration" },
        .operation_id = "tutorial_path_operation_configuration_items",
        .responses = &.{
            .{
                .status_code = .bad_request,
                .description = "Validation or input error",
            },
            .{
                .status_code = .internal_server_error,
                .description = "Unhandled server error",
            },
        },
    });
}
```

## How It Works

1. **Register the route.** `app.get(path, handler, options)` registers a `GET` handler. The third argument is the configuration struct.

2. **Set the summary.** `.summary` provides a short, human-readable label. Swagger UI displays this next to the HTTP method and path.

3. **Add a description.** `.description` supports Markdown and appears in the expanded operation detail. Use it for longer explanations, caveats, or usage notes.

4. **Organize with tags.** `.tags` groups the route in the documentation sidebar. A route can belong to multiple tag groups. Tags also appear in the top-level `tags` array of the OpenAPI document.

5. **Assign an operation ID.** `.operation_id` must be unique across the entire API. Code generators (e.g., for TypeScript or Python clients) use it to name generated functions. If omitted, Zigmund derives one from the handler name and HTTP method.

6. **Declare additional responses.** `.responses` lists non-default response codes with descriptions. The framework always generates a `200` response entry from the handler's return type; the entries here add `400`, `500`, or any other status codes your endpoint may return. These appear in the OpenAPI schema and in Swagger UI's response section.

## Key Points

- Every field in the configuration struct is optional. A bare `.{}` is valid and produces sensible defaults.
- The `.name` field is not part of the OpenAPI schema. It is used internally for route reversal (generating URLs from route names).
- Tags are ordered: the first tag determines primary grouping in most documentation tools.
- Operation IDs should follow a consistent naming convention (e.g., `module_action_resource`) to keep generated client code predictable.
- The `.responses` field is additive. It does not replace the default `200` response; it adds entries alongside it.
- You can combine route configuration with parameter-level configuration (`.description`, `.deprecated`, etc.) for a fully documented endpoint.

## See Also

- [Schema Examples](schema-extra-example.md) -- Add request and response examples to the OpenAPI schema.
- [API Metadata and Tags](metadata.md) -- Set API-level title, description, and global tag definitions.
- [Extra Models](extra-models.md) -- Use `.response_model` in route configuration to declare typed response schemas.
- [Handling Errors](handling-errors.md) -- Define custom error handlers for the status codes declared in `.responses`.
