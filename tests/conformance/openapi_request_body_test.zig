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

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, idx, needle)) |pos| {
        count += 1;
        idx = pos + needle.len;
    }
    return count;
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
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"$ref\":\"#/components/requestBodies/request_body_post_json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"$ref\":\"#/components/requestBodies/request_body_post_upload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"request_body_post_json\":{\"required\":true,\"content\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"request_body_post_upload\":{\"required\":true,\"content\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"application/json\":{\"schema\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"multipart/form-data\":{\"schema\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"file\":{\"type\":\"string\",\"format\":\"binary\"}},\"required\":[\"name\",\"file\"]}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"application/x-www-form-urlencoded\"") == null);
}

test "openapi deduplicates matching request bodies into components" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-request-body-dedupe",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/json-a", jsonHandler, .{});
    try app.post("/json-b", jsonHandler, .{});

    const doc = try app.openapi();
    try std.testing.expectEqual(
        @as(usize, 2),
        countOccurrences(doc, "\"$ref\":\"#/components/requestBodies/request_body_post_json_a\""),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(doc, "\"request_body_post_json_a\":{\"required\":true,\"content\":"),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        countOccurrences(doc, "\"request_body_post_json_b\":"),
    );
}
