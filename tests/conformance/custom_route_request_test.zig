const std = @import("std");
const zigmund = @import("zigmund");

const RequestTrace = struct {
    value: []u8,
};

fn freeRequestTrace(raw: ?*anyopaque, allocator: std.mem.Allocator) void {
    const trace: *RequestTrace = @ptrCast(@alignCast(raw orelse return));
    allocator.free(trace.value);
    allocator.destroy(trace);
}

fn requestCustomizer(req: *zigmund.Request, allocator: std.mem.Allocator) !void {
    const trace = try allocator.create(RequestTrace);
    errdefer allocator.destroy(trace);

    trace.value = try allocator.dupe(u8, req.header("x-trace-id") orelse "missing");
    errdefer allocator.free(trace.value);

    try req.setStateOwned("custom.trace", trace, freeRequestTrace);
}

fn wrappedHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const trace = req.stateAs(*RequestTrace, "custom.trace") orelse return error.MissingTrace;
    return zigmund.Response.json(allocator, .{
        .trace = trace.value,
    });
}

fn routeWrapper(
    req: *zigmund.Request,
    next: zigmund.core.HttpHandler,
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const trace = req.stateAs(*RequestTrace, "custom.trace") orelse return error.MissingTrace;
    var response = try next(req, allocator);
    errdefer response.deinit(allocator);
    try response.setHeader(allocator, "x-custom-trace", trace.value);
    return response;
}

fn includedHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const trace = req.stateAs(*RequestTrace, "custom.trace") orelse return error.MissingTrace;
    return zigmund.Response.json(allocator, .{
        .route = "included",
        .trace = trace.value,
    });
}

test "app request customizer and default route wrapper apply at runtime" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "custom-route-request",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.setRequestCustomizer(requestCustomizer);
    app.setDefaultRouteWrapper(routeWrapper);
    try app.get("/items", wrappedHandler, .{});

    var res = try app.dispatchSyntheticWithHeaders(.GET, "/items", "", &.{
        .{ .name = "x-trace-id", .value = "trace-123" },
    });
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expectEqualStrings("trace-123", res.header("x-custom-trace").?);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"trace\":\"trace-123\"") != null);
}

test "router default route wrapper survives includeRouter composition" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "custom-route-request-include-router",
        .version = "0.0.1",
    });
    defer app.deinit();

    var router = zigmund.Router.init(std.testing.allocator);
    defer router.deinit();

    app.setRequestCustomizer(requestCustomizer);
    router.setDefaultRouteWrapper(routeWrapper);
    try router.addHttpRoute(.GET, "/child", includedHandler, .{});
    try app.includeRouter("/api", &router, .{});

    var res = try app.dispatchSyntheticWithHeaders(.GET, "/api/child", "", &.{
        .{ .name = "x-trace-id", .value = "trace-router" },
    });
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expectEqualStrings("trace-router", res.header("x-custom-trace").?);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"route\":\"included\"") != null);
}
