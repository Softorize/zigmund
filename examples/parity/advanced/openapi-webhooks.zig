const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/openapi-webhooks/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .status = "ok",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/openapi-webhooks", implemented, .{
        .summary = "Parity implementation for advanced/openapi-webhooks/",
        .tags = &.{ "parity", "advanced" },
    });
}
