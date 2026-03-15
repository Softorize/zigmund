# Extra Models

Use separate Zig structs for request input and response output to control exactly which fields are accepted and which are exposed.

## Overview

Real-world APIs rarely use the same shape for input and output. A user creation endpoint might accept a username and email but return those fields plus a server-generated ID. By defining distinct structs -- one for the request body, one for the response -- you get compile-time guarantees that sensitive or internal fields never leak, and your OpenAPI documentation accurately describes both directions.

Zigmund supports this through its `Body` parameter wrapper for input and the `.response_model` route option for output. The framework generates separate OpenAPI schemas for each struct, so consumers see clear request and response contracts.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const UserIn = struct {
    username: []const u8,
    email: []const u8,
    full_name: ?[]const u8 = null,
};

const UserOut = struct {
    username: []const u8,
    email: []const u8,
    full_name: ?[]const u8 = null,
    id: u32,
};

fn createUser(
    body: zigmund.Body(UserIn, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user_in = body.value.?;
    return zigmund.Response.json(allocator, UserOut{
        .username = user_in.username,
        .email = user_in.email,
        .full_name = user_in.full_name,
        .id = 1001,
    });
}

fn getUser(
    user_id: zigmund.Path(u32, .{ .alias = "user_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, UserOut{
        .username = "alice",
        .email = "alice@example.com",
        .full_name = "Alice Wonderland",
        .id = user_id.value.?,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/extra-models/users", createUser, .{
        .summary = "Create user with separate input/output models",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_extra_models_create_user",
        .response_model = UserOut,
    });
    try app.get("/tutorial/extra-models/users/{user_id}", getUser, .{
        .summary = "Get user by ID with typed response model",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_extra_models_get_user",
        .response_model = UserOut,
    });
}
```

## How It Works

1. **Define the input model.** `UserIn` describes what the client sends: `username`, `email`, and an optional `full_name`. There is no `id` field because the server assigns it.

2. **Define the output model.** `UserOut` includes every field the client should see, including the server-generated `id`. If your application stored a password hash, that field would exist only in an internal model, never in `UserOut`.

3. **Accept the input.** `zigmund.Body(UserIn, .{})` parses the JSON request body into `UserIn`. The framework validates that required fields are present and types are correct.

4. **Map input to output.** The `createUser` handler reads the validated `UserIn`, constructs a `UserOut` with the same fields plus an assigned `id`, and returns it as JSON.

5. **Declare the response model.** `.response_model = UserOut` in the route options tells Zigmund to use `UserOut` as the schema for the `200` response in the generated OpenAPI document. This gives documentation tools the exact shape of the response payload.

6. **Reuse models across endpoints.** Both the `POST` and `GET` routes specify `.response_model = UserOut`, sharing the same response contract.

## Key Points

- Separate input and output models prevent accidental exposure of internal fields (password hashes, internal flags, audit timestamps).
- The `.response_model` option is purely for OpenAPI documentation and does not perform runtime filtering. Your handler is responsible for returning the correct struct.
- You can define as many model variants as needed: `UserIn`, `UserOut`, `UserDB`, `UserPublic`, etc.
- Optional fields (`?[]const u8 = null`) appear in the OpenAPI schema as non-required properties with nullable types.
- When multiple endpoints share a response model, changes to the struct automatically update the OpenAPI schema for all of them.

## See Also

- [Request Body](request-body.md) -- Basics of parsing JSON request bodies into structs.
- [Response Model](response-model.md) -- Filtering response fields using response models.
- [Path Operation Configuration](path-operation-configuration.md) -- Route-level options including `.response_model`.
- [Schema Examples](schema-extra-example.md) -- Add example payloads to your input and output schemas.
