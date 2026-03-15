const std = @import("std");
const zigmund = @import("zigmund");

const Item = struct {
    id: u32,
    name: []const u8,
};

const file_path = "zigmund_response_runtime_test.txt";
const stream_chunks = [_][]const u8{ "alpha", "-", "beta" };
const sse_events = [_]zigmund.Response.ServerSentEvent{
    .{
        .id = "evt-1",
        .event = "ping",
        .data = "hello",
        .retry_ms = 1500,
    },
};

fn jsonHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !Item {
    _ = req;
    _ = allocator;
    return .{
        .id = 7,
        .name = "widget",
    };
}

fn plainHandler(req: *zigmund.Request, allocator: std.mem.Allocator) ![]const u8 {
    _ = req;
    _ = allocator;
    return "plain payload";
}

fn htmlHandler(req: *zigmund.Request, allocator: std.mem.Allocator) ![]const u8 {
    _ = req;
    _ = allocator;
    return "<strong>ok</strong>";
}

fn redirectHandler(req: *zigmund.Request, allocator: std.mem.Allocator) ![]const u8 {
    _ = req;
    _ = allocator;
    return "/target";
}

fn fileHandler(req: *zigmund.Request, allocator: std.mem.Allocator) ![]const u8 {
    _ = req;
    _ = allocator;
    return file_path;
}

fn streamHandler(req: *zigmund.Request, allocator: std.mem.Allocator) ![]const []const u8 {
    _ = req;
    _ = allocator;
    return stream_chunks[0..];
}

fn sseHandler(req: *zigmund.Request, allocator: std.mem.Allocator) ![]const zigmund.Response.ServerSentEvent {
    _ = req;
    _ = allocator;
    return sse_events[0..];
}

test "plain handler returns are serialized with route response metadata" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-runtime-json",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items", jsonHandler, .{
        .status_code = .created,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var response = try client.get("/items");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.created, response.status);
    try std.testing.expectEqualStrings("application/json", response.content_type);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"id\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"name\":\"widget\"") != null);
}

test "default_response_class plain text is applied at runtime" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-runtime-plain",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/plain", plainHandler, .{
        .default_response_class = "PlainTextResponse",
    });

    var response = try app.dispatchSynthetic(.GET, "/plain", "");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("text/plain; charset=utf-8", response.content_type);
    try std.testing.expectEqualStrings("plain payload", response.body);
}

test "default_response_class html is applied at runtime" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-runtime-html",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/html", htmlHandler, .{
        .default_response_class = "HTMLResponse",
    });

    var response = try app.dispatchSynthetic(.GET, "/html", "");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("text/html; charset=utf-8", response.content_type);
    try std.testing.expectEqualStrings("<strong>ok</strong>", response.body);
}

test "default_response_class redirect is applied at runtime" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-runtime-redirect",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/go", redirectHandler, .{
        .default_response_class = "RedirectResponse",
    });

    var response = try app.dispatchSynthetic(.GET, "/go", "");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.temporary_redirect, response.status);
    try std.testing.expectEqualStrings("/target", response.header("location").?);
}

test "default_response_class file is applied at runtime" {
    try std.fs.cwd().writeFile(.{
        .sub_path = file_path,
        .data = "file payload",
    });
    defer std.fs.cwd().deleteFile(file_path) catch {};

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-runtime-file",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/file", fileHandler, .{
        .default_response_class = "FileResponse",
    });

    var response = try app.dispatchSynthetic(.GET, "/file", "");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("text/plain; charset=utf-8", response.content_type);
    try std.testing.expectEqualStrings("file payload", response.body);
}

test "default_response_class streaming is applied at runtime" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-runtime-stream",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/stream", streamHandler, .{
        .default_response_class = "StreamingResponse",
    });

    var response = try app.dispatchSynthetic(.GET, "/stream", "");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("application/octet-stream", response.content_type);
    try std.testing.expectEqualStrings("alpha-beta", response.body);
}

test "default_response_class event stream is applied at runtime" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-runtime-sse",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/events", sseHandler, .{
        .default_response_class = "EventSourceResponse",
    });

    var response = try app.dispatchSynthetic(.GET, "/events", "");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, response.status);
    try std.testing.expectEqualStrings("text/event-stream; charset=utf-8", response.content_type);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "id: evt-1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "event: ping\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "retry: 1500\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "data: hello\n") != null);
}
