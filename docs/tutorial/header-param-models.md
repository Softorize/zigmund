# Header Parameter Models

Group related HTTP request headers into a single Zig struct for clean, type-safe access in your handlers.

## Overview

APIs often rely on custom headers for tracing, versioning, or feature flags. Instead of extracting headers individually, Zigmund lets you define a struct whose fields correspond to header names and pass it to `zigmund.Header`. The framework reads the incoming request headers, maps them to struct fields, and validates that required headers are present -- all before your handler runs.

This approach is consistent with [Query Parameter Models](query-param-models.md) and [Cookie Parameter Models](cookie-param-models.md), giving every parameter source the same struct-based ergonomics.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const HeaderContext = struct {
    trace_id: []const u8,
    request_source: ?[]const u8 = null,
};

fn implemented(
    headers: zigmund.Header(HeaderContext, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = "tutorial/header-param-models/",
        .headers = headers.value.?,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/header-param-models", implemented, .{
        .summary = "Parity implementation for tutorial/header-param-models/",
        .tags = &.{ "parity", "tutorial" },
    });
}
```

## How It Works

1. **Define the model.** `HeaderContext` declares the headers you expect:
   - `trace_id` is a required `[]const u8`. Every request must include this header or the framework returns a `422` error. Zigmund maps the underscore-separated Zig field name to the conventional header name (e.g., `Trace-Id` or `trace-id`) using case-insensitive matching.
   - `request_source` is optional, defaulting to `null` when the header is not present.

2. **Wrap with `zigmund.Header`.** `zigmund.Header(HeaderContext, .{})` instructs the framework to extract and validate headers according to the struct definition.

3. **Access the values.** Inside the handler, `headers.value.?` returns a populated `HeaderContext`. Required fields are guaranteed to be present; optional fields carry either the sent value or their default.

4. **Use the data.** The struct is available for logging, tracing correlation, conditional logic, or serialization into the response.

## Key Points

- **Required vs. optional.** Fields without a default value are required. Missing required headers produce a `422 Unprocessable Entity` response with a descriptive error.
- **Name mapping.** Zig struct fields use underscores (`trace_id`), but HTTP headers use hyphens (`Trace-Id`). Zigmund performs automatic case-insensitive conversion between these conventions.
- **Type coercion.** Non-string field types (e.g., `u32`, `bool`) are automatically parsed from the header's string value.
- **OpenAPI integration.** Each field in the header model appears as an individual `in: header` parameter in the generated OpenAPI schema, with correct `required` flags and type information.
- **Reusability.** Define a common header model (e.g., for tracing or API versioning) once and reuse it across every handler that needs those headers.

## See Also

- [Header Parameters](header-params.md) -- Extract individual header values without a model struct.
- [Query Parameter Models](query-param-models.md) -- The same grouping pattern for query string parameters.
- [Cookie Parameter Models](cookie-param-models.md) -- The same grouping pattern for cookies.
- [Middleware](middleware.md) -- An alternative approach for cross-cutting header concerns that apply to all routes.
