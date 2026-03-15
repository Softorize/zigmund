# Request Reference

## Overview

`Request` represents an incoming HTTP request. It provides access to the request method, path, query parameters, headers, body, path parameters, dependency values, and background tasks. Handlers receive a `*Request` (or have parameters injected from it automatically).

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `method` | `std.http.Method` | HTTP method (GET, POST, etc.) |
| `target` | `[]const u8` | Full request target including query string |
| `path` | `[]const u8` | Request path without query string |
| `query` | `[]const u8` | Raw query string |
| `body` | `[]const u8` | Request body bytes |
| `request_id` | `?[]const u8` | Unique request identifier |
| `correlation_id` | `?[]const u8` | Correlation ID from headers |
| `peer_address` | `?std.net.Address` | Client's network address |

## UploadFile

Represents a file uploaded via multipart form data.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `filename` | `?[]const u8` | `null` | Original filename |
| `content_type` | `?[]const u8` | `null` | MIME type |
| `data` | `[]const u8` | `""` | File content bytes |

## Header Access

### `header`

```zig
pub fn header(self: *const Request, name: []const u8) ?[]const u8
```

Returns the value of the first header matching `name` (case-insensitive). Returns `null` if not found.

## Query Parameters

### `queryParam`

```zig
pub fn queryParam(self: *const Request, name: []const u8) ?[]const u8
```

Returns the value of a query parameter by name. Returns `null` if not present.

### `queryParamAll`

```zig
pub fn queryParamAll(self: *const Request, allocator: std.mem.Allocator, name: []const u8) ![]const []const u8
```

Returns all values for a query parameter (for multi-valued parameters).

## Path Parameters

### `param`

```zig
pub fn param(self: *const Request, name: []const u8) ?[]const u8
```

Returns a path parameter value by name. Path parameters are extracted from `{name}` segments in the route path.

### `paramAs`

```zig
pub fn paramAs(self: *const Request, comptime T: type, name: []const u8) !?T
```

Returns a path parameter parsed as the given type (e.g., `u32`, `i64`).

## Body Parsing

### `bodyJson`

```zig
pub fn bodyJson(self: *Request, comptime T: type) !T
```

Parses the request body as JSON into the given struct type.

### `formAs`

```zig
pub fn formAs(self: *Request, comptime T: type) !T
```

Parses URL-encoded form data into the given struct type.

### `formAsLeaky`

```zig
pub fn formAsLeaky(self: *Request, comptime T: type) !T
```

Parses URL-encoded form data, using the request arena for string allocations.

### `multipartParts`

```zig
pub fn multipartParts(self: *Request) ![]const MultipartPart
```

Parses multipart form data into individual parts.

## Dependency Values

### `dependency`

```zig
pub fn dependency(self: *const Request, name: []const u8) ?[]const u8
```

Returns the resolved value of a named dependency.

### `setDependencyValue`

```zig
pub fn setDependencyValue(self: *Request, name: []const u8, value: []const u8) !void
```

Sets a dependency value on the request (used by resolvers and middleware).

## State

### `stateAs`

```zig
pub fn stateAs(self: *const Request, comptime Ptr: type, key: []const u8) ?Ptr
```

Retrieves request-scoped state by key, cast to the given pointer type.

### `setStateBorrowed`

```zig
pub fn setStateBorrowed(self: *Request, key: []const u8, value: anytype) !void
```

Stores a borrowed pointer in request state (caller manages lifetime).

### `setStateOwned`

```zig
pub fn setStateOwned(self: *Request, key: []const u8, value: anytype, cleanup: anytype) !void
```

Stores an owned pointer in request state with a cleanup function called on request deinit.

## Validation

### `addValidationIssue`

```zig
pub fn addValidationIssue(self: *Request, issue: ValidationIssue) !void
```

Adds a validation issue to the request's issue list. Issues are reported in the error response.

### `validationIssues`

```zig
pub fn validationIssues(self: *const Request) []const ValidationIssue
```

Returns all accumulated validation issues.

## Background Tasks

### `addBackgroundTask`

Access via `self.background_tasks.add(run_fn, ctx)` to schedule work that runs after the response is sent.

## Path Parameters (Internal)

### `setPathParam`

```zig
pub fn setPathParam(self: *Request, name: []const u8, value: []const u8) !void
```

Sets a path parameter (called internally by the router during path matching).

## Example

```zig
fn handler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const user_agent = req.header("user-agent") orelse "unknown";
    const page = req.queryParam("page") orelse "1";
    const id = try req.paramAs(u32, "id") orelse return error.MissingId;

    return zigmund.Response.json(allocator, .{
        .user_agent = user_agent,
        .page = page,
        .id = id,
    });
}
```
