const std = @import("std");
const zigmund = @import("zigmund");

const JsonPayload = struct {
    name: []const u8,
};

const FormPayload = struct {
    name: []const u8,
};

fn jsonHandler(
    body: zigmund.Body(JsonPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{ .name = body.value.?.name });
}

fn multipartHandler(
    form: zigmund.Form(FormPayload, .{}),
    file: zigmund.File(zigmund.UploadFile, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .name = form.value.?.name,
        .filename = file.value.?.filename orelse "",
    });
}

test "openapi includes requestBody for injected body/form/file markers" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-request-body",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/json", jsonHandler, .{});
    try app.post("/upload", multipartHandler, .{});

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"/json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"requestBody\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"application/json\":{\"schema\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"multipart/form-data\":{\"schema\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"file\":{\"type\":\"string\",\"format\":\"binary\"}},\"required\":[\"name\",\"file\"]}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"application/x-www-form-urlencoded\"") == null);
}
