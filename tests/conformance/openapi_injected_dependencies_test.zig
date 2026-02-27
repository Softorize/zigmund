const std = @import("std");
const zigmund = @import("zigmund");

fn traceProvider(req: *zigmund.Request) ?[]const u8 {
    return req.queryParam("trace");
}

fn authProvider(req: *zigmund.Request) ?[]const u8 {
    const token = req.queryParam("token") orelse return null;
    if (std.mem.eql(u8, token, "secret")) return "alice";
    return null;
}

fn secureHandler(
    trace: zigmund.Depends(traceProvider, .{ .name = "trace_ctx", .use_cache = false }),
    auth: zigmund.SecurityNamed(authProvider, "auth", &.{"items:read"}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .trace = trace.value,
        .user = auth.value.?,
    });
}

test "openapi includes injected dependency and security metadata" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "openapi-injected",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addSecurityScheme("auth", .{
        .http = .{
            .scheme = "bearer",
            .bearer_format = "JWT",
        },
    });

    try app.get("/secure", secureHandler, .{});

    const doc = try app.openapi();
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"x-zigmund-dependencies\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"trace_ctx\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"name\":\"auth\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"security\":[{\"auth\":[\"items:read\"]}]") != null);
}
