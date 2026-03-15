const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/debugging/";

fn debugInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .request_id = req.requestId() orelse "none",
        .method = @tagName(req.method),
        .path = req.path,
        .debug = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    // Enable structured observability sinks for development debugging
    app.enableJsonAccessLogSink();
    app.enableJsonTelemetrySink();
    app.enableJsonTraceSink();

    try app.get("/tutorial/debugging", debugInfo, .{
        .summary = "Debug endpoint with verbose observability sinks enabled",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_debugging_info",
    });
}
