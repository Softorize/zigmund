const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/uploadfile/";

/// Demonstrates File marker and UploadFile struct for file uploads.
fn uploadHandler(
    file: zigmund.File(zigmund.UploadFile, .{ .description = "File to upload" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const upload = file.value.?;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .filename = upload.filename,
        .content_type = upload.content_type,
        .size = upload.data.len,
        .upload_file_fields = .{
            .filename = "?[]const u8 - original filename",
            .content_type = "?[]const u8 - MIME type",
            .data = "[]const u8 - file bytes",
        },
    });
}

fn uploadInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .marker = "zigmund.File(zigmund.UploadFile, FileOptions)",
        .file_options = .{
            .media_type = "default 'application/octet-stream'",
            .description = "optional description for OpenAPI",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/reference/uploadfile/upload", uploadHandler, .{
        .summary = "File upload with UploadFile struct",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_uploadfile_upload",
    });
    try app.get("/reference/uploadfile", uploadInfo, .{
        .summary = "File marker and UploadFile API reference",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_uploadfile_overview",
    });
}
