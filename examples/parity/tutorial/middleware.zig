const std = @import("std");
const zigmund = @import("zigmund");

fn requestMiddleware(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try req.setDependencyValue("middleware_stage", "request");
}

fn responseMiddleware(
    req: *zigmund.Request,
    response: *zigmund.Response,
    allocator: std.mem.Allocator,
) !void {
    _ = req;
    try response.setHeader(allocator, "x-middleware", "enabled");
}

fn readMiddlewareState(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .stage = req.dependency("middleware_stage") orelse "",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addMiddleware(zigmund.Middleware{
        .name = "tutorial_middleware",
        .request_hook = requestMiddleware,
        .response_hook = responseMiddleware,
    });
    try app.get("/tutorial/middleware", readMiddlewareState, .{
        .summary = "Request and response middleware behavior",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_middleware_state",
    });
}
