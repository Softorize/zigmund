const std = @import("std");
const zigmund = @import("zigmund");

fn negotiatedHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const ct_tag = req.dependency("_content_type") orelse "unknown";
    const ct = zigmund.ContentType.fromTagName(ct_tag) orelse return zigmund.Response.text("unknown");

    return switch (ct) {
        .json => zigmund.Response.json(allocator, .{ .format = "json" }),
        .html => zigmund.Response.html("<p>html</p>"),
        .plain_text => zigmund.Response.text("plain text"),
        .xml => blk: {
            var resp = zigmund.Response.text("<root>xml</root>");
            resp.content_type = "application/xml";
            break :blk resp;
        },
        .any => zigmund.Response.json(allocator, .{ .format = "default" }),
    };
}

fn buildApp() !zigmund.App {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "content-negotiation-test",
        .version = "0.0.1",
    });
    try app.addMiddleware(zigmund.contentNegotiationMw(.{
        .default = .json,
        .supported = &.{ .json, .plain_text, .html, .xml },
    }));
    try app.get("/data", negotiatedHandler, .{});
    return app;
}

test "Accept: application/json returns json response" {
    var app = try buildApp();
    defer app.deinit();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/data", "", &.{
        .{ .name = "accept", .value = "application/json" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("application/json", response.content_type);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"format\":\"json\"") != null);
}

test "Accept: text/html returns html response" {
    var app = try buildApp();
    defer app.deinit();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/data", "", &.{
        .{ .name = "accept", .value = "text/html" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("text/html; charset=utf-8", response.content_type);
    try std.testing.expectEqualStrings("<p>html</p>", response.body);
}

test "Accept: */* returns default (json) response" {
    var app = try buildApp();
    defer app.deinit();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/data", "", &.{
        .{ .name = "accept", .value = "*/*" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("application/json", response.content_type);
}

test "no Accept header returns default (json) response" {
    var app = try buildApp();
    defer app.deinit();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.get("/data");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("application/json", response.content_type);
}

test "Accept: text/plain returns plain text response" {
    var app = try buildApp();
    defer app.deinit();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/data", "", &.{
        .{ .name = "accept", .value = "text/plain" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("text/plain; charset=utf-8", response.content_type);
    try std.testing.expectEqualStrings("plain text", response.body);
}

test "Accept: application/xml returns xml response" {
    var app = try buildApp();
    defer app.deinit();

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();
    var response = try client.requestWithHeaders(.GET, "/data", "", &.{
        .{ .name = "accept", .value = "application/xml" },
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("application/xml", response.content_type);
    try std.testing.expectEqualStrings("<root>xml</root>", response.body);
}
