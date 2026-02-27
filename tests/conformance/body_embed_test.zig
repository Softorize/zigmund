const std = @import("std");
const zigmund = @import("zigmund");

const Payload = struct {
    name: []const u8,
};

fn embeddedBodyHandler(
    body: zigmund.Body(Payload, .{ .embed = true }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .name = body.value.?.name,
    });
}

fn optionalEmbeddedBodyHandler(
    body: zigmund.Body(?Payload, .{ .embed = true }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .has_body = body.value.? != null,
        .name = if (body.value.?) |payload| payload.name else "",
    });
}

test "body embed parses nested body payload" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "body-embed",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/embed", embeddedBodyHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var ok = try client.post("/embed", "{\"body\":{\"name\":\"zig\"}}");
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"name\":\"zig\"") != null);

    var missing_embed = try client.post("/embed", "{\"name\":\"zig\"}");
    defer missing_embed.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, missing_embed.status);
}

test "optional embedded body allows empty object" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "body-embed-optional",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/embed-optional", optionalEmbeddedBodyHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var empty = try client.post("/embed-optional", "{}");
    defer empty.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, empty.status);
    try std.testing.expect(std.mem.indexOf(u8, empty.body, "\"has_body\":false") != null);

    var provided = try client.post("/embed-optional", "{\"body\":{\"name\":\"zig\"}}");
    defer provided.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, provided.status);
    try std.testing.expect(std.mem.indexOf(u8, provided.body, "\"has_body\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, provided.body, "\"name\":\"zig\"") != null);
}

test "openapi requestBody for embedded body uses body field" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "body-embed-openapi",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/embed", embeddedBodyHandler, .{});

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/embed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"application/json\":{\"schema\":{\"type\":\"object\",\"properties\":{\"body\":{\"type\":\"object\"}},\"required\":[\"body\"]}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"properties\":{\"name\"") == null);
}
