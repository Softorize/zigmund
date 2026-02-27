const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/stream-data/";

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    const events = [_]zigmund.Response.ServerSentEvent{
        .{
            .id = "1",
            .event = "parity",
            .retry_ms = 1500,
            .data = "{\"page\":\"advanced/stream-data/\",\"status\":\"ok\"}",
        },
        .{
            .id = "2",
            .event = "parity",
            .data = "{\"done\":true}",
        },
    };
    return zigmund.Response.eventStream(allocator, &events);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/stream-data", implemented, .{
        .summary = "Parity implementation for advanced/stream-data/",
        .tags = &.{ "parity", "advanced" },
    });
}
