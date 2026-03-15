# Parameters Reference

## Overview

Zigmund uses compile-time parameter markers to declare how handler function arguments are extracted from the incoming request. Each marker is a generic type that wraps a value type and carries extraction options.

All parameter markers produce a struct with a `value: ?T` field. The framework populates this field before calling the handler.

## Parameter Markers

### `Query`

```zig
pub fn Query(comptime T: type, opts: QueryOptions) type
```

Extracts a value from the URL query string.

**QueryOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `alias` | `?[]const u8` | `null` | Query parameter name (overrides the Zig parameter name) |
| `description` | `?[]const u8` | `null` | Description for OpenAPI |
| `required` | `bool` | `true` | Whether the parameter is required |
| `deprecated` | `bool` | `false` | Mark as deprecated in OpenAPI |
| `gt` | `?f64` | `null` | Value must be greater than this |
| `ge` | `?f64` | `null` | Value must be greater than or equal to this |
| `lt` | `?f64` | `null` | Value must be less than this |
| `le` | `?f64` | `null` | Value must be less than or equal to this |
| `min_length` | `?usize` | `null` | Minimum string length |
| `max_length` | `?usize` | `null` | Maximum string length |
| `pattern` | `?[]const u8` | `null` | Regex pattern for validation |
| `enum_values` | `[]const []const u8` | `&.{}` | Allowed values |
| `strict` | `bool` | `false` | Strict type coercion |
| `openapi_examples` | `[]const OpenApiExample` | `&.{}` | Parameter examples for OpenAPI |

### `Path`

```zig
pub fn Path(comptime T: type, opts: PathOptions) type
```

Extracts a value from the URL path. Path parameters are declared with `{name}` in the route path.

**PathOptions:** Same fields as QueryOptions except no `required` or `deprecated` fields.

### `Header`

```zig
pub fn Header(comptime T: type, opts: HeaderOptions) type
```

Extracts a value from a request header.

**HeaderOptions:** Same fields as QueryOptions plus:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `convert_underscores` | `bool` | `true` | Convert underscores to hyphens in the header name |

### `Cookie`

```zig
pub fn Cookie(comptime T: type, opts: CookieOptions) type
```

Extracts a value from a request cookie.

**CookieOptions:** Same constraint fields as QueryOptions.

### `Body`

```zig
pub fn Body(comptime T: type, opts: BodyOptions) type
```

Parses the request body as JSON into the given struct type.

**BodyOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `embed` | `bool` | `false` | Embed the body value under a key |
| `media_type` | `[]const u8` | `"application/json"` | Expected media type |
| `description` | `?[]const u8` | `null` | Description for OpenAPI |
| `gt` | `?f64` | `null` | Numeric constraint |
| `ge` | `?f64` | `null` | Numeric constraint |
| `lt` | `?f64` | `null` | Numeric constraint |
| `le` | `?f64` | `null` | Numeric constraint |
| `min_length` | `?usize` | `null` | Minimum length constraint |
| `max_length` | `?usize` | `null` | Maximum length constraint |
| `pattern` | `?[]const u8` | `null` | Regex pattern |
| `enum_values` | `[]const []const u8` | `&.{}` | Allowed values |
| `strict` | `bool` | `false` | Strict validation |

### `Form`

```zig
pub fn Form(comptime T: type, opts: FormOptions) type
```

Parses URL-encoded form data into the given struct type.

**FormOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `media_type` | `[]const u8` | `"application/x-www-form-urlencoded"` | Expected media type |
| `description` | `?[]const u8` | `null` | Description for OpenAPI |
| (constraint fields) | | | Same as BodyOptions |

### `File`

```zig
pub fn File(comptime T: type, opts: FileOptions) type
```

Extracts an uploaded file from multipart form data.

**FileOptions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `media_type` | `[]const u8` | `"application/octet-stream"` | Expected media type |
| `description` | `?[]const u8` | `null` | Description for OpenAPI |
| (constraint fields) | | | Same as BodyOptions |

## Usage Pattern

All parameter markers produce a struct with a `value: ?T` field:

```zig
fn handler(
    name: zigmund.Query([]const u8, .{ .alias = "name" }),
    id: zigmund.Path(u32, .{ .alias = "id" }),
    body: zigmund.Body(CreateRequest, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const query_name = name.value orelse "default";
    const path_id = id.value.?;
    const request_body = body.value.?;
    // ...
}
```

The framework's compile-time injector inspects the handler's parameter types at comptime and generates extraction code for each marker.

## Example

```zig
const CreateUserRequest = struct {
    name: []const u8,
    email: []const u8,
    age: ?u32 = null,
};

fn createUser(
    body: zigmund.Body(CreateUserRequest, .{ .description = "User to create" }),
    x_request_id: zigmund.Header([]const u8, .{ .alias = "x-request-id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user = body.value.?;
    const request_id = x_request_id.value orelse "none";
    return zigmund.Response.json(allocator, .{
        .name = user.name,
        .request_id = request_id,
    });
}
```
