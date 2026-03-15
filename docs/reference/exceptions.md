# Exceptions Reference

## Overview

Zigmund provides structured error types for HTTP and WebSocket error handling, as well as RFC 7807 Problem Details for standardized error responses.

## HTTPException

```zig
pub const HTTPException = struct {
    status_code: std.http.Status,
    detail: []const u8,
    headers: []const std.http.Header = &.{},
};
```

Represents an HTTP error with a status code, detail message, and optional additional headers. Used with exception handlers registered via `app.addExceptionHandler`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `status_code` | `std.http.Status` | (required) | HTTP status code |
| `detail` | `[]const u8` | (required) | Human-readable error message |
| `headers` | `[]const std.http.Header` | `&.{}` | Additional response headers |

## WebSocketException

```zig
pub const WebSocketException = struct {
    code: u16,
    reason: []const u8,
};
```

Represents a WebSocket close frame with a status code and reason.

| Field | Type | Description |
|-------|------|-------------|
| `code` | `u16` | WebSocket close code (e.g., 1000, 1008) |
| `reason` | `[]const u8` | Human-readable close reason |

## ProblemDetail (RFC 7807)

```zig
pub const ProblemDetail = struct {
    type_uri: []const u8 = "about:blank",
    title: []const u8,
    status: u16,
    detail: ?[]const u8 = null,
    instance: ?[]const u8 = null,
};
```

Implements RFC 7807 Problem Details for HTTP APIs. Responses use `Content-Type: application/problem+json`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `type_uri` | `[]const u8` | `"about:blank"` | URI identifying the problem type |
| `title` | `[]const u8` | (required) | Short human-readable summary |
| `status` | `u16` | (required) | HTTP status code |
| `detail` | `?[]const u8` | `null` | Detailed explanation of this occurrence |
| `instance` | `?[]const u8` | `null` | URI identifying this specific occurrence |

## Problem Response Functions

### `problemResponse`

```zig
pub fn problemResponse(allocator: std.mem.Allocator, problem: ProblemDetail) !Response
```

Creates a JSON response from a `ProblemDetail` with `Content-Type: application/problem+json`.

### Convenience Constructors

Each function accepts an allocator and an optional detail message:

```zig
pub fn problemNotFound(allocator: std.mem.Allocator, detail: ?[]const u8) !Response
pub fn problemBadRequest(allocator: std.mem.Allocator, detail: ?[]const u8) !Response
pub fn problemUnauthorized(allocator: std.mem.Allocator, detail: ?[]const u8) !Response
pub fn problemForbidden(allocator: std.mem.Allocator, detail: ?[]const u8) !Response
pub fn problemConflict(allocator: std.mem.Allocator, detail: ?[]const u8) !Response
pub fn problemUnprocessableEntity(allocator: std.mem.Allocator, detail: ?[]const u8) !Response
pub fn problemInternalServerError(allocator: std.mem.Allocator, detail: ?[]const u8) !Response
```

## Exception Handlers

Register custom exception handlers for specific error sets:

```zig
const AppError = error{
    ItemNotFound,
    InvalidInput,
};

fn handleAppError(req: *zigmund.Request, err: anyerror, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return switch (err) {
        error.ItemNotFound => zigmund.problemNotFound(allocator, "Item not found"),
        error.InvalidInput => zigmund.problemBadRequest(allocator, "Invalid input"),
        else => zigmund.problemInternalServerError(allocator, null),
    };
}

try app.addExceptionHandler(AppError, handleAppError);
```

## Example

```zig
fn handler(allocator: std.mem.Allocator) !zigmund.Response {
    // Return a 404 with RFC 7807 format
    return zigmund.problemNotFound(allocator, "User with ID 42 was not found");
}

fn customProblem(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.problemResponse(allocator, .{
        .type_uri = "https://example.com/probs/out-of-credit",
        .title = "Out of Credit",
        .status = 403,
        .detail = "Your current balance is 30, but that costs 50.",
        .instance = "/account/12345/msgs/abc",
    });
}
```
