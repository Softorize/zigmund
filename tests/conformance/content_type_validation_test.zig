const std = @import("std");
const zigmund = @import("zigmund");

const JsonPayload = struct {
    name: []const u8,
};

const FormPayload = struct {
    name: []const u8,
};

fn jsonHandler(body: zigmund.Body(JsonPayload, .{}), allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .name = body.value.?.name });
}

fn formHandler(form: zigmund.Form(FormPayload, .{}), allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .name = form.value.?.name });
}

fn fileHandler(file: zigmund.File([]const u8, .{}), allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .size = file.value.?.len });
}

test "marker content type mismatches return 415 when header is present" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "content-type",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/json", jsonHandler, .{});
    try app.post("/form", formHandler, .{});
    try app.post("/file", fileHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var bad_json = try client.postWithHeaders("/json", "{\"name\":\"x\"}", &.{
        .{ .name = "content-type", .value = "text/plain" },
    });
    defer bad_json.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unsupported_media_type, bad_json.status);

    var bad_form = try client.postWithHeaders("/form", "name=x", &.{
        .{ .name = "content-type", .value = "application/json" },
    });
    defer bad_form.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unsupported_media_type, bad_form.status);

    var bad_file = try client.postWithHeaders("/file", "abcdef", &.{
        .{ .name = "content-type", .value = "application/octet-stream" },
    });
    defer bad_file.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unsupported_media_type, bad_file.status);

    var no_header_file = try client.post("/file", "abcdef");
    defer no_header_file.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, no_header_file.status);
}
