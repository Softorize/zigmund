# Advanced Dependencies

Build complex dependency injection chains with nested dependencies, parameterized providers, and caching. Zigmund's compile-time dependency injection supports composing multiple dependencies within a single handler.

## Overview

Zigmund's dependency injection system goes beyond simple single-level injection. Dependencies can themselves depend on other dependencies, creating a graph of providers that the framework resolves automatically. The `zigmund.Depends()` type marker declares a dependency, and the framework calls the provider function, injects its own parameters, and passes the result to the handler.

This is the Zig equivalent of FastAPI's `Depends()` with nested sub-dependencies.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

// --- Base dependency: provides a common query parameter ---
fn commonPagination(
    skip: zigmund.Query(u32, .{ .alias = "skip", .description = "Number of items to skip", .required = false }),
    limit: zigmund.Query(u32, .{ .alias = "limit", .description = "Max items to return", .required = false }),
    allocator: std.mem.Allocator,
) ![]const u8 {
    const s = skip.value orelse 0;
    const l = limit.value orelse 10;
    return std.fmt.allocPrint(allocator, "skip={d}&limit={d}", .{ s, l });
}

// --- Second dependency: depends on the first (nested pattern) ---
fn dbSession(req: *zigmund.Request) []const u8 {
    _ = req;
    return "active-db-session";
}

fn readItems(
    pagination: zigmund.Depends(commonPagination, .{}),
    db: zigmund.Depends(dbSession, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .pagination = pagination.value.?,
        .db_session = db.value.?,
    });
}

fn readItemsSingle(
    pagination: zigmund.Depends(commonPagination, .{ .use_cache = true }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .pagination = pagination.value.?,
        .cached = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/items", readItems, .{
        .summary = "Read items with nested dependency injection",
    });
    try app.get("/items-cached", readItemsSingle, .{
        .summary = "Read items with cached dependency",
    });
}
```

## How It Works

### 1. Declaring Dependencies

Use `zigmund.Depends(provider_fn, options)` as a parameter type in your handler:

```zig
fn myHandler(
    dep: zigmund.Depends(myProvider, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const value = dep.value.?;
    // use value...
}
```

The framework calls `myProvider`, resolves its parameters (which can include Query, Path, Request, or even other Depends), and injects the return value into `dep.value`.

### 2. Dependency Providers

A dependency provider is a regular function whose parameters follow the same injection rules as handlers. It can accept:

- `*zigmund.Request` -- the raw request.
- `std.mem.Allocator` -- the per-request allocator.
- `zigmund.Query(...)` -- query parameters.
- `zigmund.Path(...)` -- path parameters.
- `zigmund.Depends(...)` -- other dependencies (nested).

The return type is the value that will be injected into the handler.

### 3. Multiple Dependencies

A handler can declare multiple `Depends` parameters. The framework resolves each one independently:

```zig
fn readItems(
    pagination: zigmund.Depends(commonPagination, .{}),
    db: zigmund.Depends(dbSession, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    // Both pagination and db are resolved before this handler runs
}
```

### 4. Dependency Caching

When the same dependency is used by multiple parts of the handler chain, you can enable caching to avoid calling the provider more than once per request:

```zig
pagination: zigmund.Depends(commonPagination, .{ .use_cache = true }),
```

With `.use_cache = true`, the framework stores the result of the first invocation and reuses it for subsequent references within the same request. This is particularly useful when nested dependencies share a common provider.

### 5. Nested Dependencies

Dependencies can depend on other dependencies. The framework builds a resolution graph at compile time and calls providers in the correct order:

```
Handler
  |-- Depends(commonPagination)
  |     |-- Query("skip")
  |     |-- Query("limit")
  |     |-- Allocator
  |-- Depends(dbSession)
        |-- *Request
```

## Key Points

- `zigmund.Depends()` enables compile-time dependency injection with full type safety.
- Provider functions follow the same parameter injection rules as handlers.
- Multiple dependencies can be composed within a single handler.
- Use `.use_cache = true` to avoid redundant provider calls within a single request.
- The dependency graph is resolved at compile time, producing zero-overhead dispatch.
- Dependencies automatically contribute to OpenAPI documentation (e.g., query parameters declared in a provider appear in the spec).

## See Also

- [Testing Dependencies](testing-dependencies.md) -- override dependencies with mocks for testing.
- [Using the Request Directly](using-request-directly.md) -- access the raw request in providers.
- [Security](security.md) -- security schemes as dependencies.
