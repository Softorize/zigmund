const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/custom-request-and-route/";

const RequestInfo = struct {
    trace: []u8,
};

fn cleanupRequestInfo(raw: ?*anyopaque, allocator: std.mem.Allocator) void {
    const info: *RequestInfo = @ptrCast(@alignCast(raw orelse return));
    allocator.free(info.trace);
    allocator.destroy(info);
}

fn installCustomRequest(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    const info = try allocator.create(RequestInfo);
    errdefer allocator.destroy(info);

    info.trace = try allocator.dupe(u8, req.header("x-trace-id") orelse "generated-trace");
    errdefer allocator.free(info.trace);

    try req.setStateOwned("parity.custom_request", info, cleanupRequestInfo);
}

fn traceWrappingRoute(
    req: *zigmund.Request,
    next: zigmund.core.HttpHandler,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const info = req.stateAs(*RequestInfo, "parity.custom_request") orelse return error.MissingCustomRequestState;
    var response = try next(req, allocator);
    errdefer response.deinit(allocator);
    try response.setHeader(allocator, "x-route-trace", info.trace);
    return response;
}

fn implemented(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const info = req.stateAs(*RequestInfo, "parity.custom_request") orelse return error.MissingCustomRequestState;
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .trace = info.trace,
        .wrapped = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    app.setRequestCustomizer(installCustomRequest);
    app.setDefaultRouteWrapper(traceWrappingRoute);
    try app.get("/how-to/custom-request-and-route", implemented, .{
        .summary = "Parity implementation for how-to/custom-request-and-route/",
        .tags = &.{ "parity", "how-to" },
    });
}
