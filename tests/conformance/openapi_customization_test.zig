const std = @import("std");
const zigmund = @import("zigmund");

const OpenApiDeterministicModelA = struct {
    name: []const u8,
};

const OpenApiDeterministicModelB = struct {
    name: []const u8,
};

fn okHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .ok = true });
}

fn modelAHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .name = "a" });
}

fn modelBHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{ .name = "b" });
}

fn wsHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = conn;
    _ = allocator;
}

test "openapi deterministic mode sorts paths and methods and emits extensions" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-customization",
        .version = "0.0.1",
        .openapi_deterministic = true,
        .openapi_extensions = &.{.{
            .key = "x-company",
            .value_json = "{\"tier\":\"enterprise\"}",
        }},
    });
    defer app.deinit();

    try app.post("/sorted", okHandler, .{});
    try app.get("/sorted", okHandler, .{});

    try app.get("/z-last", modelBHandler, .{
        .response_model = OpenApiDeterministicModelB,
    });
    try app.get("/a-first", modelAHandler, .{
        .response_model = OpenApiDeterministicModelA,
        .openapi_extensions = &.{.{
            .key = "x-rate-limit",
            .value_json = "{\"rpm\":120}",
        }},
    });
    try app.websocket("/ws/room", wsHandler, .{
        .openapi_extensions = &.{.{
            .key = "x-ws-policy",
            .value_json = "\"strict\"",
        }},
    });

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"x-company\":{\"tier\":\"enterprise\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"x-rate-limit\":{\"rpm\":120}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"x-ws-policy\":\"strict\"") != null);

    const a_index = std.mem.indexOf(u8, doc, "\"/a-first\":") orelse return error.TestUnexpectedResult;
    const z_index = std.mem.indexOf(u8, doc, "\"/z-last\":") orelse return error.TestUnexpectedResult;
    try std.testing.expect(a_index < z_index);

    const get_index = std.mem.indexOf(u8, doc, "\"get\":{\"operationId\":\"get_sorted\"") orelse
        return error.TestUnexpectedResult;
    const post_index = std.mem.indexOf(u8, doc, "\"post\":{\"operationId\":\"post_sorted\"") orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(get_index < post_index);

    const model_a_index = std.mem.indexOf(u8, doc, "OpenApiDeterministicModelA") orelse
        return error.TestUnexpectedResult;
    const model_b_index = std.mem.indexOf(u8, doc, "OpenApiDeterministicModelB") orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(model_a_index < model_b_index);
}

test "openapi rejects non extension keys that do not start with x-" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-invalid-extension-key",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/bad", okHandler, .{
        .openapi_extensions = &.{.{
            .key = "company",
            .value_json = "true",
        }},
    });

    try std.testing.expectError(error.InvalidOpenApiExtensionKey, app.openapi());
}

test "openapi rejects invalid extension json values" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-invalid-extension-json",
        .version = "0.0.1",
        .openapi_extensions = &.{.{
            .key = "x-company",
            .value_json = "{not-json}",
        }},
    });
    defer app.deinit();

    try std.testing.expectError(error.InvalidOpenApiExtensionJson, app.openapi());
}
