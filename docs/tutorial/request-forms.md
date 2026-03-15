# Request Forms

Zigmund can parse HTML form submissions sent as `application/x-www-form-urlencoded` data. Use the `zigmund.Form()` marker type to bind form fields directly to a Zig struct.

## Overview

When a browser submits an HTML `<form>` (without file uploads), the data is encoded as `application/x-www-form-urlencoded` -- key-value pairs separated by `&`. Zigmund's `Form()` marker parses this encoding and populates a struct with the submitted values, giving you type-safe access to form data.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const LoginForm = struct {
    username: []const u8,
    password: []const u8,
};

fn login(
    form: zigmund.Form(LoginForm, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .username = form.value.?.username,
        .accepted = true,
    });
}
```

Register the route:

```zig
try app.post("/login", login, .{});
```

## How It Works

1. **Define a form struct.** `LoginForm` declares the expected fields. Each field name must match the form field name sent by the client.
2. **Declare the parameter.** `form: zigmund.Form(LoginForm, .{})` tells Zigmund to parse the request body as URL-encoded form data and populate the struct.
3. **Access form data.** `form.value.?` unwraps the parsed struct. Access individual fields like `.username` and `.password`.

## Key Points

- **Content type.** The request must use `Content-Type: application/x-www-form-urlencoded`. This is the default for HTML `<form>` elements without the `enctype` attribute.
- **Field matching.** Struct field names must match the form field names exactly. If the client sends `user_name` but the struct has `username`, the field will not be populated.
- **Type coercion.** String fields (`[]const u8`) receive the raw value. Numeric fields (`u32`, `f64`, etc.) are automatically parsed from the string representation.
- **Required fields.** All non-optional struct fields are required. If a required field is missing from the form data, Zigmund returns a validation error.
- **Optional fields.** Use optional types (`?[]const u8`, `?u32`) for fields that may or may not be present in the submission.
- **Not for file uploads.** `Form()` handles `application/x-www-form-urlencoded` only. For file uploads, use `File()` with `multipart/form-data`. See [Forms and Files](request-forms-and-files.md) for combining both.

## See Also

- [Request Form Models](request-form-models.md) -- Structured form models with descriptions and metadata.
- [Request Files](request-files.md) -- Handling file uploads with multipart data.
- [Forms and Files](request-forms-and-files.md) -- Combining form fields and file uploads.
- [Request Body](request-body.md) -- Handling JSON request bodies as an alternative to forms.
