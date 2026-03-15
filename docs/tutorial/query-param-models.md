# Query Parameter Models

Group related query parameters into a single Zig struct, giving your handlers a clean, self-documenting interface instead of a long list of individual parameters.

## Overview

As endpoints accumulate query parameters -- filters, pagination, sorting -- handler signatures grow unwieldy. Zigmund lets you define a struct whose fields represent the individual query keys, then pass the entire struct to `zigmund.Query`. The framework maps each field name to a query key, applies default values for omitted parameters, and deserializes the result into your struct automatically.

This approach provides several advantages:

- **Readability.** One parameter replaces many.
- **Reusability.** The same model can be shared across multiple endpoints.
- **Documentation.** The struct definition serves as a single source of truth for all allowed query parameters, and Zigmund reflects it in the OpenAPI schema.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const QueryFilters = struct {
    q: ?[]const u8 = null,
    limit: u32 = 10,
    tags: []const []const u8 = &.{},
};

fn implemented(
    filters: zigmund.Query(QueryFilters, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = "tutorial/query-param-models/",
        .filters = filters.value.?,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/query-param-models", implemented, .{
        .summary = "Parity implementation for tutorial/query-param-models/",
        .tags = &.{ "parity", "tutorial" },
    });
}
```

## How It Works

1. **Define the model.** `QueryFilters` is a plain Zig struct. Each field corresponds to a query parameter:
   - `q` is an optional string. When omitted from the URL, it defaults to `null`.
   - `limit` is a `u32` that defaults to `10` when not provided.
   - `tags` is a slice of strings, defaulting to an empty slice. Repeated query keys (e.g., `?tags=a&tags=b`) are collected into the slice.

2. **Wrap with `zigmund.Query`.** `zigmund.Query(QueryFilters, .{})` tells the framework to populate the struct from the query string. The second argument is a comptime options struct (empty here, but you can set `.description`, etc.).

3. **Access the values.** Inside the handler, `filters.value.?` unwraps the populated `QueryFilters` instance. All fields carry their parsed or default values.

4. **Serialization to the response.** Passing `filters.value.?` directly to `Response.json` serializes every field, including nested slices.

## Key Points

- Fields with default values (`= null`, `= 10`, `= &.{}`) become optional query parameters. Fields without defaults are required -- omitting them triggers a `422` error.
- Slice fields (`[]const []const u8`) collect multiple values for the same key, e.g., `?tags=api&tags=v2` produces `&.{ "api", "v2" }`.
- You can compose query models with [string validations](query-params-str-validations.md) by using individual `zigmund.Query` parameters alongside a model, or by adding validation options to the model-level declaration.
- The struct is reflected as individual parameters in the OpenAPI schema, not as a JSON body, matching how tools like Swagger UI render query parameters.
- Reuse the same struct across endpoints for consistent parameter contracts. For instance, a `PaginationParams` model could be shared by every list endpoint.

## See Also

- [Query Parameters](query-parameters.md) -- Basics of individual query parameter extraction.
- [Query Parameter String Validations](query-params-str-validations.md) -- Apply string constraints to individual query parameters.
- [Cookie Parameter Models](cookie-param-models.md) -- The same struct-based grouping pattern applied to cookies.
- [Header Parameter Models](header-param-models.md) -- The same struct-based grouping pattern applied to headers.
