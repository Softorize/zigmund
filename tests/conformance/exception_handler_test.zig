const std = @import("std");
const zigmund = @import("zigmund");

const DomainErrors = error{
    Boom,
    Outage,
};

fn boomRoute(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return error.Boom;
}

fn outageRoute(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return error.Outage;
}

fn domainExceptionHandler(req: *zigmund.Request, err: anyerror, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var res = try zigmund.Response.json(allocator, .{
        .kind = @errorName(err),
        .handled = true,
    });
    return res.withStatus(.bad_request);
}

fn wildcardExceptionHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var res = try zigmund.Response.json(allocator, .{
        .kind = "wildcard",
        .handled = true,
    });
    return res.withStatus(.teapot);
}

test "custom exception handler handles matching error set" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "exception-handler",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addExceptionHandler(DomainErrors, domainExceptionHandler);
    try app.get("/boom", boomRoute, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/boom");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.bad_request, response.status);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"kind\":\"Boom\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"handled\":true") != null);
}

test "wildcard anyerror exception handler catches unmatched errors" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "exception-handler-wildcard",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addExceptionHandler(anyerror, wildcardExceptionHandler);
    try app.get("/outage", outageRoute, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/outage");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.teapot, response.status);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"kind\":\"wildcard\"") != null);
}

test "unhandled route errors return 500 response" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "exception-handler-fallback",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/outage", outageRoute, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/outage");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.internal_server_error, response.status);
    try std.testing.expectEqualStrings("internal server error", response.body);
}
