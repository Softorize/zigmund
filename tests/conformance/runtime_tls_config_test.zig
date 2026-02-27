const std = @import("std");
const zigmund = @import("zigmund");

var saw_serve_failed: bool = false;
var serve_failed_detail: ?[]u8 = null;

fn resetAuditState(allocator: std.mem.Allocator) void {
    saw_serve_failed = false;
    if (serve_failed_detail) |detail| allocator.free(detail);
    serve_failed_detail = null;
}

fn auditSink(event: zigmund.App.AuditEvent, allocator: std.mem.Allocator) !void {
    if (!std.mem.eql(u8, event.action, "serve_failed")) return;
    saw_serve_failed = true;

    if (serve_failed_detail) |detail| allocator.free(detail);
    serve_failed_detail = try allocator.dupe(u8, event.detail);
}

test "tls startup validates certificate and key paths" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "tls-config",
        .version = "0.0.1",
    });
    defer app.deinit();

    const result = app.serve(.{
        .host = "127.0.0.1",
        .port = 0,
        .worker_count = 1,
        .tls = .{
            .cert_pem_path = "/definitely/missing/cert.pem",
            .key_pem_path = "/definitely/missing/key.pem",
        },
    });

    try std.testing.expectError(error.TlsCertificateLoadFailed, result);
}

test "tls startup failure emits serve_failed audit event" {
    resetAuditState(std.testing.allocator);
    defer resetAuditState(std.testing.allocator);

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "tls-config-audit",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.setAuditSink(auditSink);

    const result = app.serve(.{
        .host = "127.0.0.1",
        .port = 0,
        .worker_count = 1,
        .tls = .{
            .cert_pem_path = "/definitely/missing/cert.pem",
            .key_pem_path = "/definitely/missing/key.pem",
        },
    });

    try std.testing.expectError(error.TlsCertificateLoadFailed, result);
    try std.testing.expect(saw_serve_failed);
    try std.testing.expectEqualStrings("TlsCertificateLoadFailed", serve_failed_detail orelse "");
}
