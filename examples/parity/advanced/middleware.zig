const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/middleware/";

var request_count = std.atomic.Value(u64).init(0);

fn requestCounter(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = req;
    _ = allocator;
    _ = request_count.fetchAdd(1, .monotonic);
}

fn responseTimer(_: *zigmund.Request, response: *zigmund.Response, allocator: std.mem.Allocator) !void {
    try response.setHeader(allocator, "x-process-time", "0");
}

fn middlewareStatus(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .total_requests = request_count.load(.monotonic),
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addMiddleware(zigmund.App.Middleware{
        .name = "request-counter",
        .request_hook = requestCounter,
    });
    try app.addMiddleware(zigmund.App.Middleware{
        .name = "response-timer",
        .response_hook = responseTimer,
    });

    try app.get("/advanced/middleware", middlewareStatus, .{
        .summary = "Show middleware request counter",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_middleware_status",
    });
}
