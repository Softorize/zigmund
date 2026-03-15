# Forms and Files

Zigmund supports receiving both form fields and file uploads in a single `multipart/form-data` request. Declare a `zigmund.Form()` parameter for the form fields and a `zigmund.File()` parameter for the uploaded file.

## Overview

Some endpoints need both structured form data (text fields, checkboxes) and file uploads in the same request. For example, a profile update might include a username (text field) and an avatar image (file). Zigmund handles this by combining `Form()` and `File()` parameters in the same handler.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

const ProfileForm = struct {
    username: []const u8,
    bio: []const u8,
};

fn updateProfile(
    form: zigmund.Form(ProfileForm, .{
        .media_type = "multipart/form-data",
        .description = "Profile metadata",
    }),
    avatar: zigmund.File(zigmund.UploadFile, .{
        .description = "Profile avatar image",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const data = form.value.?;
    const file = avatar.value.?;
    return zigmund.Response.json(allocator, .{
        .username = data.username,
        .bio = data.bio,
        .avatar_filename = file.filename,
        .avatar_content_type = file.content_type,
        .avatar_bytes = file.data.len,
    });
}
```

Register the route:

```zig
try app.post("/profile", updateProfile, .{});
```

## How It Works

1. **Form parameter.** `zigmund.Form(ProfileForm, .{ .media_type = "multipart/form-data" })` parses the text fields from the multipart body. Setting `.media_type` to `"multipart/form-data"` tells Zigmund (and the OpenAPI spec) that this form is part of a multipart request, not a URL-encoded one.
2. **File parameter.** `zigmund.File(zigmund.UploadFile, .{ .description = "Profile avatar image" })` extracts the file part from the same multipart body.
3. **Single request.** Both parameters are populated from the same `multipart/form-data` request body. Zigmund separates text parts from file parts automatically.
4. **Access the data.** `form.value.?` gives you the struct with text fields. `avatar.value.?` gives you the `UploadFile` with filename, content type, and raw bytes.

## Key Points

- **Media type matters.** When combining forms and files, set `.media_type = "multipart/form-data"` on the `Form()` parameter. Without this, the form defaults to `application/x-www-form-urlencoded`, which cannot carry file data.
- **Descriptions for OpenAPI.** The `.description` option on both `Form()` and `File()` adds documentation to the OpenAPI schema, making the Swagger UI more informative.
- **Multiple files.** You can declare multiple `zigmund.File()` parameters to accept several files in one request. Each file parameter corresponds to a different form field name.
- **Optional files.** If the file is not required, check `avatar.value` for `null` before unwrapping.
- **Field name matching.** The parameter name in the handler signature (e.g., `avatar`) determines which multipart field name Zigmund looks for. The client must send the file under a matching field name.

## See Also

- [Request Forms](request-forms.md) -- Handling form data without file uploads.
- [Request Files](request-files.md) -- Handling file uploads without additional form fields.
- [Request Form Models](request-form-models.md) -- Structured form models with validation.
