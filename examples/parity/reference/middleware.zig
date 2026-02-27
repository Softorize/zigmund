const std = @import("std");
const zigmund = @import("zigmund");

fn referenceRequestMiddleware(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try req.setDependencyValue("reference_middleware", "applied");
}

fn referenceResponseMiddleware(
    req: *zigmund.Request,
    response: *zigmund.Response,
    allocator: std.mem.Allocator,
) !void {
    _ = req;
    try response.setHeader(allocator, "x-reference-middleware", "applied");
}

fn middlewareReference(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .state = req.dependency("reference_middleware") orelse "",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addMiddleware(zigmund.Middleware{
        .name = "reference_middleware",
        .request_hook = referenceRequestMiddleware,
        .response_hook = referenceResponseMiddleware,
    });

    try app.get("/reference/middleware", middlewareReference, .{
        .summary = "Middleware reference behavior and hook order",
        .tags = &.{ "parity", "reference" },
        .operation_id = "reference_middleware_state",
    });
}
