# UploadFile Reference

## Overview

`UploadFile` represents a file uploaded via multipart form data. It is a nested type within `Request` and is re-exported at the top level as `zigmund.UploadFile`.

## Type Definition

```zig
pub const UploadFile = struct {
    filename: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
    data: []const u8 = "",
};
```

## Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `filename` | `?[]const u8` | `null` | Original filename from the upload |
| `content_type` | `?[]const u8` | `null` | MIME type of the uploaded file |
| `data` | `[]const u8` | `""` | Raw file content bytes |

## Usage with File Parameter

Use the `File` parameter marker to declare file upload parameters in handlers:

```zig
const zigmund = @import("zigmund");

fn uploadHandler(
    file: zigmund.File(zigmund.UploadFile, .{
        .description = "File to upload",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const upload = file.value.?;
    return zigmund.Response.json(allocator, .{
        .filename = upload.filename orelse "unknown",
        .content_type = upload.content_type orelse "application/octet-stream",
        .size = upload.data.len,
    });
}
```

## Accessing Multipart Parts Directly

For lower-level control, access multipart parts via the request:

```zig
fn handler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const parts = try req.multipartParts();
    for (parts) |part| {
        // part.name, part.filename, part.content_type, part.data
    }
    return zigmund.Response.json(allocator, .{ .parts = parts.len });
}
```

## Example

```zig
try app.post("/upload", uploadHandler, .{
    .summary = "Upload a file",
});
```
