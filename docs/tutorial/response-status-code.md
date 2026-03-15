# Response Status Code

Set custom HTTP status codes on responses and in OpenAPI documentation.

## Overview

By default, Zigmund returns HTTP 200 (OK) for successful responses. Many APIs need different status codes -- for instance, 201 (Created) when a new resource is created, or 204 (No Content) for a successful deletion. Zigmund gives you two complementary ways to control the status code: setting it directly on the response object, and declaring it in the route options for OpenAPI documentation.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const TaskPayload = struct { title: []const u8 };

fn createTask(
    payload: zigmund.Body(TaskPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // Build the JSON response as usual.
    var response = try zigmund.Response.json(allocator, .{
        .title = payload.value.?.title,
        .status = "created",
    });
    // Override the default 200 status with 201 Created.
    response.status = .created;
    return response;
}

// Registration -- .status_code tells OpenAPI that 201 is the expected success code.
// app.post("/tasks", createTask, .{ .status_code = .created })
```

### Request example

```bash
curl -X POST http://127.0.0.1:8000/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Write documentation"}'
```

Response (HTTP 201):

```json
{"title": "Write documentation", "status": "created"}
```

## How It Works

### 1. Setting the status on the response

After creating a response, assign the `.status` field:

```zig
var response = try zigmund.Response.json(allocator, .{ .ok = true });
response.status = .created;
return response;
```

Alternatively, use the `.withStatus()` method for a chainable style:

```zig
return (try zigmund.Response.json(allocator, .{ .ok = true })).withStatus(.created);
```

Both approaches produce the same result.

### 2. Declaring status_code in route options

The `.status_code` field in `RouteOptions` does not change the actual HTTP response -- it tells the OpenAPI generator what the expected success status code is:

```zig
try app.post("/tasks", createTask, .{
    .status_code = .created,
});
```

For correct behavior, set the status in both places: on the response (to actually send the right code) and in the route options (so the documentation is accurate).

### 3. Common status codes

Zigmund uses `std.http.Status` from the Zig standard library. Here are the most common values:

| Enum value           | Code | Typical use                                    |
|----------------------|------|------------------------------------------------|
| `.ok`                | 200  | Successful GET, PUT, PATCH.                    |
| `.created`           | 201  | Successful POST that creates a resource.       |
| `.no_content`        | 204  | Successful DELETE with no response body.       |
| `.bad_request`       | 400  | Client sent invalid data.                      |
| `.unauthorized`      | 401  | Authentication required.                       |
| `.forbidden`         | 403  | Authenticated but not authorized.              |
| `.not_found`         | 404  | Resource does not exist.                       |
| `.conflict`          | 409  | Resource state conflict.                       |
| `.unprocessable_entity` | 422 | Validation error.                            |
| `.internal_server_error` | 500 | Unexpected server error.                    |

### 4. Text and HTML responses with status codes

Status codes are not limited to JSON responses. Every response type supports them:

```zig
fn healthCheck(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("OK").withStatus(.ok);
}
```

### 5. No-content responses

For endpoints that should return no body (e.g., DELETE), return an empty text response with status 204:

```zig
fn deleteTask(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return zigmund.Response.text("").withStatus(.no_content);
}
```

## Key Points

- The default response status is 200 (OK). Override it by setting `response.status` or using `.withStatus()`.
- Set `.status_code` in the route options to update the OpenAPI documentation -- it does not change the actual response.
- Status codes use `std.http.Status`, a standard library enum with all standard HTTP status codes.
- For resource creation endpoints, use `.created` (201) by convention.
- For delete endpoints with no response body, use `.no_content` (204).

## See Also

- [Handling Errors](handling-errors.md) -- returning error status codes from exception handlers.
- [Response Model](response-model.md) -- filtering response fields.
- [Request Body](request-body.md) -- accepting data in POST/PUT/PATCH routes.
