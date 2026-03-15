const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/cors/";

fn corsProtectedEndpoint(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .message = "This endpoint is protected by CORS middleware",
        .allowed_origins = "https://example.com",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.addMiddleware(zigmund.corsMw(.{
        .allowed_origins = &.{"https://example.com"},
        .allowed_methods = &.{ "GET", "POST", "OPTIONS" },
        .allowed_headers = &.{ "Content-Type", "Authorization" },
        .allow_credentials = true,
        .max_age = 3600,
    }));
    try app.get("/tutorial/cors", corsProtectedEndpoint, .{
        .summary = "Endpoint protected by CORS middleware",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_cors_protected_endpoint",
    });
}
