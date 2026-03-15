const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/staticfiles/";

/// Demonstrates StaticFilesIntegration: init, withOptions, and mount.
fn staticFilesInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .api = .{
            .init = "StaticFilesIntegration.init(directory)",
            .with_options = "integration.withOptions(.{ .index_file, .cache_control, .allow_hidden })",
            .mount = "integration.mount(app, prefix) or mountStaticFiles(app, prefix, dir, opts)",
        },
        .options = .{
            .index_file = "default 'index.html'",
            .cache_control = "default 'public, max-age=60'",
            .allow_hidden = "default false",
            .include_in_schema = "default false",
        },
        .example_mount = "/reference/staticfiles/assets",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/staticfiles", staticFilesInfo, .{
        .summary = "StaticFilesIntegration API reference",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_staticfiles_overview",
    });
}
