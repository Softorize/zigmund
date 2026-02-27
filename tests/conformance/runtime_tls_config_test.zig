const std = @import("std");
const zigmund = @import("zigmund");

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
