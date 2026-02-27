const std = @import("std");
const zigmund = @import("zigmund");

fn setSession(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var response = try zigmund.Response.json(allocator, .{
        .set = true,
    });
    try response.setCookie(allocator, "session", "s-1", .{
        .path = "/",
        .http_only = true,
    });
    return response;
}

fn readSession(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .session = req.cookie("session"),
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/reference/testclient/session", setSession, .{
        .summary = "Set cookie for TestClient persistence checks",
        .tags = &.{ "parity", "reference" },
        .operation_id = "reference_testclient_set_session",
    });
    try app.get("/reference/testclient/session", readSession, .{
        .summary = "Read persisted cookie from TestClient request",
        .tags = &.{ "parity", "reference" },
        .operation_id = "reference_testclient_read_session",
    });
}
