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

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/request-files/upload", uploadFile, .{
        .summary = "Accept and inspect uploaded file content",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_request_files_upload",
    });
}
