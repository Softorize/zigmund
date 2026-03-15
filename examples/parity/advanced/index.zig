const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/";

fn advancedIndex(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .section = "Advanced User Guide",
        .topics = &[_][]const u8{
            "additional-responses",
            "additional-status-codes",
            "advanced-dependencies",
            "behind-a-proxy",
            "custom-response",
            "events",
            "middleware",
            "openapi-callbacks",
            "openapi-webhooks",
            "security",
            "settings",
            "sub-applications",
            "templates",
            "testing-dependencies",
            "testing-events",
            "testing-websockets",
            "websockets",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/index", advancedIndex, .{
        .summary = "Advanced User Guide index listing all advanced topics",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_index",
    });
}
