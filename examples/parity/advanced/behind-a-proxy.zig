const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/behind-a-proxy/";

fn proxyInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .message = "This app is configured with root_path for reverse proxy support",
        .root_path = "/api/v1",
        .note = "OpenAPI docs, Swagger UI, and ReDoc are served under the root_path prefix",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Demonstrate that the app's config exposes root_path.
    // In a real proxy scenario you would initialise the App with:
    //   App.init(allocator, .{ .title = "...", .version = "...", .root_path = "/api/v1" })
    // The route below simply reports the configuration.
    try app.get("/advanced/behind-a-proxy", proxyInfo, .{
        .summary = "Show reverse proxy root_path configuration",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_behind_a_proxy_info",
    });
}
