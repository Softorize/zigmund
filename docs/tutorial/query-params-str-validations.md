# Query Parameter String Validations

Apply string-specific constraints -- minimum length, maximum length, and regex patterns -- to query parameters so that invalid input is rejected before your handler runs.

## Overview

When a query parameter is a string, you often need more than just "present or absent." Zigmund lets you attach validation rules directly to the `zigmund.Query` declaration using comptime options. The framework checks every incoming request against those rules and returns a `422 Unprocessable Entity` response automatically when a constraint is violated.

Supported string constraints:

| Option       | Type            | Description                                      |
|--------------|-----------------|--------------------------------------------------|
| `min_length` | `comptime_int`  | Minimum number of bytes the value must contain.   |
| `max_length` | `comptime_int`  | Maximum number of bytes the value may contain.    |
| `pattern`    | `[]const u8`    | POSIX-style regex the value must match.           |

These constraints are also propagated to the generated OpenAPI schema, so interactive documentation (Swagger UI, Redoc) displays them to API consumers.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn searchItems(
    q: zigmund.Query([]const u8, .{
        .alias = "q",
        .required = false,
        .min_length = 3,
        .max_length = 50,
        .pattern = "^[A-Za-z0-9 _-]+$",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .query = q.value,
        .matched = .{ "alpha", "beta" },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/query-params-str-validations/search", searchItems, .{
        .summary = "Validate string query params",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_validate_string_query_params",
    });
}
```

## How It Works

1. **Declare the parameter.** `zigmund.Query([]const u8, .{ ... })` tells the framework that the handler expects a query-string parameter whose value is a string (`[]const u8`). The second argument is a comptime options struct.

2. **Set the alias.** `.alias = "q"` maps the Zig field to the query key `?q=...`. Without an alias, Zigmund uses the Zig parameter name.

3. **Mark as optional.** `.required = false` means the endpoint still succeeds when `q` is omitted. In that case `q.value` is `null`.

4. **Apply string constraints.** When `q` is present, Zigmund checks:
   - The value is at least 3 bytes long (`min_length`).
   - The value is at most 50 bytes long (`max_length`).
   - The value matches the regex `^[A-Za-z0-9 _-]+$` (`pattern`).

   If any check fails, the framework short-circuits with a `422` response containing a structured validation error -- your handler is never called.

5. **Access the value.** Inside the handler, `q.value` is `?[]const u8`. When the parameter was supplied and passed validation, it contains the string; otherwise it is `null`.

## Key Points

- Validation runs at the framework level before your handler executes, so you never need to manually check lengths or patterns inside business logic.
- The `pattern` option accepts a POSIX-compatible regular expression string. It is compiled once at startup, not on every request.
- All constraints are reflected in the OpenAPI schema under the parameter's `schema` object (`minLength`, `maxLength`, `pattern`), giving API consumers immediate feedback in generated documentation.
- Combine `.required = false` with `.min_length` safely: the length check only applies when the parameter is actually present.
- You can use string validations alongside other query parameter options such as `.description` and `.deprecated`.

## See Also

- [Query Parameters](query-parameters.md) -- Basics of query parameter extraction and type conversion.
- [Path Parameter Numeric Validations](path-params-numeric-validations.md) -- Equivalent numeric constraints for path parameters.
- [Query Parameter Models](query-param-models.md) -- Group multiple query parameters into a single struct.
- [Schema Examples](schema-extra-example.md) -- Add example values alongside validation constraints in OpenAPI output.
