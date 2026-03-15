# Response Model

Filter and shape outgoing JSON responses using a response model struct.

## Overview

Sometimes your handler builds a response with more data than you want the client to see. For example, you might construct a user object internally with an email and admin flag, but only want to expose the user's ID and username to the outside world. Rather than manually stripping fields, you can declare a `response_model` in the route options. Zigmund will automatically filter the response so that only the fields present in the model struct are included.

This is the Zigmund equivalent of FastAPI's `response_model` parameter. It acts as an output schema, ensuring that your API never accidentally leaks internal fields.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// The response model -- only these fields will appear in the API response.
const PublicUser = struct {
    id: u32,
    username: []const u8,
};

fn readUser(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    // The handler returns more fields than the client should see.
    return zigmund.Response.json(allocator, .{
        .id = 7,
        .username = "alice",
        .email = "alice@example.com", // Will be filtered out.
        .admin = true,                // Will be filtered out.
    });
}

// Registration -- response_model restricts the output to PublicUser fields.
// app.get("/users/me", readUser, .{ .response_model = PublicUser })
```

### What the client receives

```json
{
  "id": 7,
  "username": "alice"
}
```

The `email` and `admin` fields are stripped because they do not exist in `PublicUser`.

## How It Works

### 1. Define the response model struct

Create a struct that contains only the fields you want to expose:

```zig
const PublicUser = struct {
    id: u32,
    username: []const u8,
};
```

This struct acts as a contract with your API consumers. It also becomes the response schema in the generated OpenAPI documentation.

### 2. Set response_model in route options

Pass the struct type as `.response_model` when registering the route:

```zig
try app.get("/users/me", readUser, .{
    .response_model = PublicUser,
});
```

### 3. Handler returns full data

Your handler can construct the response with any fields it likes. Zigmund applies the response model as a post-processing filter:

```zig
fn readUser(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .id = 7,
        .username = "alice",
        .email = "alice@example.com",
        .admin = true,
    });
}
```

Only the fields that match `PublicUser` by name pass through. Everything else is discarded.

### 4. Additional response model options

The `RouteOptions` struct provides fine-grained control over response shaping:

| Option                          | Type                  | Default | Description                                    |
|---------------------------------|-----------------------|---------|------------------------------------------------|
| `response_model`                | `?type`               | `null`  | Struct type used to filter fields.             |
| `response_model_include`        | `[]const []const u8`  | `&.{}`  | Allowlist of field names to include.           |
| `response_model_exclude`        | `[]const []const u8`  | `&.{}`  | Denylist of field names to exclude.            |
| `response_model_exclude_unset`  | `bool`                | `false` | Exclude fields not explicitly set.             |
| `response_model_exclude_defaults`| `bool`               | `false` | Exclude fields that equal their default value. |
| `response_model_exclude_none`   | `bool`                | `false` | Exclude fields with null values.               |

### 5. Separate handler data from API contract

A key design benefit: your handler logic and your public API shape are independent. You can refactor internal data structures without changing the API contract, as long as the response model stays the same.

## Key Points

- `response_model` filters the JSON response to include only the fields defined in the model struct.
- Fields present in the handler's response but absent from the response model are silently removed -- they never reach the client.
- The response model struct is used to generate the response schema in the OpenAPI documentation.
- This approach prevents accidental data leaks (internal fields, sensitive data) without requiring manual field-by-field construction in every handler.
- You can combine `response_model` with `response_model_exclude` or `response_model_include` for additional control.

## See Also

- [Request Body](request-body.md) -- using structs as input models.
- [Response Status Code](response-status-code.md) -- customizing the HTTP status code.
- [First Steps](first-steps.md) -- the basic Response.json constructor.
