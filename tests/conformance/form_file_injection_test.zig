const std = @import("std");
const zigmund = @import("zigmund");

const FormPayload = struct {
    name: []const u8,
    qty: u8,
};

fn formHandler(
    form: zigmund.Form(FormPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .name = form.value.?.name,
        .qty = form.value.?.qty,
    });
}

fn fileHandler(
    file: zigmund.File([]const u8, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const bytes = file.value.?;
    return zigmund.Response.json(allocator, .{
        .size = bytes.len,
        .body = bytes,
    });
}

fn multipartHandler(
    form: zigmund.Form(FormPayload, .{}),
    file: zigmund.File([]const u8, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .name = form.value.?.name,
        .qty = form.value.?.qty,
        .file = file.value.?,
    });
}

fn uploadMetaHandler(
    file: zigmund.File(zigmund.UploadFile, .{ .media_type = "text/plain" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .filename = file.value.?.filename orelse "",
        .content_type = file.value.?.content_type orelse "",
        .data = file.value.?.data,
    });
}

fn multiUploadHandler(
    files: zigmund.File([]const zigmund.UploadFile, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const items = files.value.?;
    return zigmund.Response.json(allocator, .{
        .count = items.len,
        .first = if (items.len > 0) (items[0].filename orelse "") else "",
        .second = if (items.len > 1) (items[1].filename orelse "") else "",
    });
}

test "form and file parameter injection" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "form-file",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/forms", formHandler, .{});
    try app.post("/files", fileHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var form_ok = try client.post("/forms", "name=zig+lang&qty=7");
    defer form_ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, form_ok.status);
    try std.testing.expect(std.mem.indexOf(u8, form_ok.body, "\"name\":\"zig lang\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, form_ok.body, "\"qty\":7") != null);

    var form_bad = try client.post("/forms", "name=zig&qty=bad");
    defer form_bad.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, form_bad.status);
    try std.testing.expect(std.mem.indexOf(u8, form_bad.body, "\"loc\":[\"body\",\"qty\"]") != null);

    var file_ok = try client.post("/files", "abcdef");
    defer file_ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, file_ok.status);
    try std.testing.expect(std.mem.indexOf(u8, file_ok.body, "\"size\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, file_ok.body, "\"body\":\"abcdef\"") != null);
}

test "multipart form-data injection with file" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "multipart",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/multipart", multipartHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    const body =
        "--zigmund-boundary\r\n" ++
        "Content-Disposition: form-data; name=\"name\"\r\n\r\n" ++
        "zigmund\r\n" ++
        "--zigmund-boundary\r\n" ++
        "Content-Disposition: form-data; name=\"qty\"\r\n\r\n" ++
        "9\r\n" ++
        "--zigmund-boundary\r\n" ++
        "Content-Disposition: form-data; name=\"upload\"; filename=\"hello.txt\"\r\n" ++
        "Content-Type: text/plain\r\n\r\n" ++
        "abc123\r\n" ++
        "--zigmund-boundary--";

    var ok = try client.postWithHeaders("/multipart", body, &.{
        .{ .name = "content-type", .value = "multipart/form-data; boundary=zigmund-boundary" },
    });
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"name\":\"zigmund\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"qty\":9") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"file\":\"abc123\"") != null);
}

test "upload file metadata marker and per-file media type validation" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "upload-meta",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/upload", uploadMetaHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    const body_ok =
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\n" ++
        "Content-Type: text/plain\r\n\r\n" ++
        "hello\r\n" ++
        "--b--";

    var ok = try client.postWithHeaders("/upload", body_ok, &.{
        .{ .name = "content-type", .value = "multipart/form-data; boundary=b" },
    });
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"filename\":\"a.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"content_type\":\"text/plain\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"data\":\"hello\"") != null);

    const body_bad =
        "--b\r\n" ++
        "Content-Disposition: form-data; name=\"file\"; filename=\"a.bin\"\r\n" ++
        "Content-Type: application/octet-stream\r\n\r\n" ++
        "raw\r\n" ++
        "--b--";

    var bad = try client.postWithHeaders("/upload", body_bad, &.{
        .{ .name = "content-type", .value = "multipart/form-data; boundary=b" },
    });
    defer bad.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unsupported_media_type, bad.status);
}

test "multipart multi-file injection returns upload file slices" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "upload-multi",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/multi", multiUploadHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    const body =
        "--m\r\n" ++
        "Content-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\n" ++
        "Content-Type: text/plain\r\n\r\n" ++
        "a\r\n" ++
        "--m\r\n" ++
        "Content-Disposition: form-data; name=\"file\"; filename=\"b.txt\"\r\n" ++
        "Content-Type: text/plain\r\n\r\n" ++
        "b\r\n" ++
        "--m--";

    var ok = try client.postWithHeaders("/multi", body, &.{
        .{ .name = "content-type", .value = "multipart/form-data; boundary=m" },
    });
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"count\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"first\":\"a.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"second\":\"b.txt\"") != null);
}
