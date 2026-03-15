# Request Files

Zigmund handles file uploads sent as `multipart/form-data`. Declare a parameter with the `zigmund.File()` marker type to receive uploaded file data, including the filename, content type, and raw bytes.

## Overview

When a client uploads a file (typically through an HTML `<input type="file">` element or a multipart API call), the request body is encoded as `multipart/form-data`. Zigmund parses the multipart payload and delivers each file part as a `zigmund.UploadFile` struct containing the file's metadata and content.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn uploadFile(
    file: zigmund.File(zigmund.UploadFile, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .filename = file.value.?.filename,
        .content_type = file.value.?.content_type,
        .bytes = file.value.?.data.len,
    });
}
```

Register the route:

```zig
try app.post("/upload", uploadFile, .{});
```

## How It Works

1. **Declare the parameter.** The handler parameter `file: zigmund.File(zigmund.UploadFile, .{})` tells Zigmund to extract a file from the multipart request body.
2. **Automatic parsing.** Zigmund parses the `multipart/form-data` payload and populates the `UploadFile` struct with the file's metadata.
3. **Access file data.** The `file.value.?` expression unwraps the uploaded file. The `UploadFile` struct contains:
   - `.filename` -- the original filename from the client.
   - `.content_type` -- the MIME type of the uploaded file (e.g., `"image/png"`).
   - `.data` -- the raw file bytes as a `[]const u8` slice.

## Key Points

- **Content type requirement.** The request must use `Content-Type: multipart/form-data`. Zigmund returns an error if the content type does not match.
- **File size.** The `.data` field contains the entire file in memory. For very large files, consider streaming or setting server-level size limits.
- **Optional files.** If the file parameter should be optional, the `File()` marker handles this through the `.value` optional. Check for `null` if the file may not be present.
- **Multiple files.** To accept multiple files in a single request, declare multiple `zigmund.File()` parameters with different names, or use `zigmund.File` with an array type.
- **OpenAPI documentation.** The `File()` marker automatically generates the correct `multipart/form-data` schema in the OpenAPI spec, so Swagger UI renders a file upload widget.

## See Also

- [Request Forms](request-forms.md) -- Handling form-urlencoded data without files.
- [Forms and Files](request-forms-and-files.md) -- Combining form fields and file uploads in a single request.
- [Request Body](request-body.md) -- Handling JSON request bodies.
