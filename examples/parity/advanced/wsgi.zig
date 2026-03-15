const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/wsgi/";

/// Zig uses a native HTTP server — there is no WSGI/ASGI adapter layer.
/// zigmund.App is configured directly with AppConfig and runs via
/// app.listen(). This example shows how the Zig equivalent works:
/// create the app, register routes, and start listening.

fn serverInfo(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .runtime = "native Zig HTTP server",
        .protocol = "HTTP/1.1",
        .wsgi_equivalent = "not applicable — Zig runs natively",
        .message = "zigmund.App runs directly without WSGI/ASGI; configure with AppConfig and call app.listen()",
    });
}

/// Usage (standalone server — not used in parity test suite):
///
///   var app = try zigmund.App.init(allocator, .{
///       .title = "My App",
///       .version = "1.0",
///   });
///   defer app.deinit();
///
///   // Register routes...
///   try app.get("/", handler, .{});
///
///   // Start the native server
///   try app.listen(.{ .port = 8000 });

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/wsgi", serverInfo, .{
        .summary = "Native Zig server — no WSGI/ASGI needed",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_wsgi_native_server",
    });
}
