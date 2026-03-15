# How to Add a GraphQL Endpoint

This recipe shows how to mount a GraphQL endpoint with an interactive playground.

## Problem

You want to add a GraphQL API endpoint alongside your REST routes, with optional GET support and a GraphQL playground.

## Solution

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn graphqlExecutor(
    query: []const u8,
    operation_name: ?[]const u8,
    variables_json: ?[]const u8,
    req: *zigmund.Request,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    _ = req;
    // Execute your GraphQL query here and return the result
    return zigmund.Response.json(allocator, .{
        .data = .{
            .query = query,
            .operation = operation_name orelse "",
            .variables = variables_json orelse "",
        },
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigmund.App.init(allocator, .{
        .title = "My API",
        .version = "1.0.0",
    });
    defer app.deinit();

    try zigmund.mountGraphQl(&app, "/graphql", graphqlExecutor, .{
        .allow_get = true,
        .playground = true,
    });

    try app.serve(.{ .port = 8080 });
}
```

## Explanation

The `mountGraphQl` function registers a GraphQL endpoint on your app. It takes four arguments:

1. A pointer to the `App`.
2. The endpoint path (e.g., `"/graphql"`).
3. An executor function that receives the parsed query, operation name, variables, the raw request, and an allocator. It must return a `Response`.
4. A `GraphQlOptions` struct.

**GraphQlOptions fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `allow_get` | `bool` | `true` | Allow GraphQL queries via GET requests |
| `playground` | `bool` | `true` | Serve an interactive GraphQL playground UI |
| `include_in_schema` | `bool` | `true` | Include the endpoint in the OpenAPI schema |

When `playground` is enabled, visiting the endpoint in a browser serves an interactive GraphQL IDE. POST requests to the endpoint execute GraphQL operations.

## See Also

- [App Reference](../reference/app.md)
