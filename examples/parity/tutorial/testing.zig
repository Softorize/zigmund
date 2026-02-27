const std = @import("std");
const zigmund = @import("zigmund");

fn ping(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .ping = "pong",
    });
}

fn echoBody(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .body = req.body,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/testing/ping", ping, .{
        .summary = "Endpoint used by in-process TestClient assertions",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_testing_ping",
    });
    try app.post("/tutorial/testing/echo", echoBody, .{
        .summary = "Echo payload for testing assertions",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_testing_echo",
    });
}
