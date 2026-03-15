# Path Parameter Numeric Validations

Constrain numeric path parameters with minimum, maximum, and other numeric rules so that out-of-range values are rejected before your handler executes.

## Overview

Path parameters extracted from the URL are often numeric IDs, version numbers, or page indices. Zigmund lets you declare numeric bounds directly in the `zigmund.Path` comptime options. When an incoming value violates a constraint, the framework returns a `422 Unprocessable Entity` response with a structured error message -- your handler never sees the invalid data.

Supported numeric constraints:

| Option | Type   | Description                                        |
|--------|--------|----------------------------------------------------|
| `gt`   | number | Value must be **greater than** this bound.          |
| `ge`   | number | Value must be **greater than or equal to** this bound. |
| `lt`   | number | Value must be **less than** this bound.             |
| `le`   | number | Value must be **less than or equal to** this bound. |

These constraints are propagated to the OpenAPI schema (`minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`), giving API consumers clear documentation of valid ranges.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn readVersion(
    version: zigmund.Path(i64, .{
        .alias = "version",
        .ge = 1,
        .le = 10,
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .version = version.value.?,
        .valid = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/path-params-numeric-validations/{version}", readVersion, .{
        .summary = "Validate numeric path params with constraints",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_validate_numeric_path_params",
    });
}
```

## How It Works

1. **Declare the parameter.** `zigmund.Path(i64, .{ ... })` extracts the `{version}` segment from the URL and parses it as a signed 64-bit integer.

2. **Set the alias.** `.alias = "version"` connects this parameter to the `{version}` placeholder in the route pattern. The alias must match the name inside the braces.

3. **Apply numeric bounds.** `.ge = 1` requires the value to be at least 1. `.le = 10` requires the value to be at most 10. A request to `/tutorial/path-params-numeric-validations/0` or `/tutorial/path-params-numeric-validations/11` would be rejected with a validation error.

4. **Access the value.** Inside the handler, `version.value.?` unwraps the parsed integer. Path parameters are always present (the route would not match otherwise), so `.?` is safe here.

5. **Automatic error responses.** If the parsed integer falls outside `[1, 10]`, Zigmund returns a `422` response with details about which constraint was violated. The handler is never called.

## Key Points

- You can combine multiple constraints freely. For example, `.gt = 0, .lt = 100` restricts a value to the open interval (0, 100).
- Constraints work with any integer type (`u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`) as well as floating-point types (`f32`, `f64`).
- The OpenAPI schema for the parameter automatically includes `minimum` / `maximum` (or their exclusive variants), so Swagger UI and other tools can validate input client-side.
- If the URL segment cannot be parsed as the declared numeric type at all (e.g., a string where an integer is expected), Zigmund returns a `422` before constraint checks even run.
- Numeric validations on path parameters pair naturally with string validations on query parameters to fully describe your endpoint's contract.

## See Also

- [Path Parameters](path-parameters.md) -- Basics of path parameter extraction and type conversion.
- [Query Parameter String Validations](query-params-str-validations.md) -- String-specific constraints for query parameters.
- [Extra Data Types](extra-data-types.md) -- Specialized numeric and temporal types for parameters.
- [Path Operation Configuration](path-operation-configuration.md) -- Additional route-level metadata for OpenAPI.
