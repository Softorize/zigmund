const std = @import("std");
const zigmund = @import("zigmund");

fn readStaticInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .static_prefix = "/tutorial/static-files/assets",
        .example_file = "/tutorial/static-files/assets/index.html",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try zigmund.mountStaticFiles(
        app,
        "/tutorial/static-files/assets",
        "examples/parity/assets/static",
        .{
            .include_in_schema = true,
            .cache_control = "public, max-age=300",
        },
    );

    try app.get("/tutorial/static-files", readStaticInfo, .{
        .summary = "Static files mount example",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_static_files_info",
    });
}
