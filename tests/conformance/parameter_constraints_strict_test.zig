const std = @import("std");
const zigmund = @import("zigmund");

fn constrainedHandler(
    page: zigmund.Query(i64, .{
        .alias = "page",
        .ge = 1,
        .le = 10,
    }),
    tag: zigmund.Query([]const u8, .{
        .alias = "tag",
        .min_length = 3,
        .max_length = 5,
        .pattern = "^ab",
        .enum_values = &.{ "abc", "abz" },
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = page.value,
        .tag = tag.value,
    });
}

fn boolHandler(
    active: zigmund.Query(bool, .{
        .alias = "active",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .active = active.value,
    });
}

fn strictMarkerBoolHandler(
    active: zigmund.Query(bool, .{
        .alias = "active",
        .strict = true,
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .active = active.value,
    });
}

test "query constraints enforce ge/le/min_length/max_length/pattern/enum" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "constraints",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/search", constrainedHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var ok = try client.get("/search?page=3&tag=abc");
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);

    var bad_ge = try client.get("/search?page=0&tag=abc");
    defer bad_ge.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, bad_ge.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_ge.body, "\"type\":\"ge\"") != null);

    var bad_enum = try client.get("/search?page=3&tag=axx");
    defer bad_enum.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, bad_enum.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_enum.body, "\"type\":\"enum\"") != null);
}

test "route strict validation rejects permissive bool coercion" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "route-strict",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/flags", boolHandler, .{
        .strict_validation = true,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var strict_fail = try client.get("/flags?active=1");
    defer strict_fail.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, strict_fail.status);
    try std.testing.expect(std.mem.indexOf(u8, strict_fail.body, "\"type\":\"strict_bool\"") != null);

    var strict_ok = try client.get("/flags?active=false");
    defer strict_ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, strict_ok.status);
}

test "global strict validation can be overridden per-route" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "global-strict",
        .version = "0.0.1",
        .strict_validation = true,
    });
    defer app.deinit();

    try app.get("/strict", boolHandler, .{});
    try app.get("/permissive", boolHandler, .{
        .strict_validation = false,
    });

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var strict_fail = try client.get("/strict?active=1");
    defer strict_fail.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, strict_fail.status);
    try std.testing.expect(std.mem.indexOf(u8, strict_fail.body, "\"type\":\"strict_bool\"") != null);

    var permissive_ok = try client.get("/permissive?active=1");
    defer permissive_ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, permissive_ok.status);
}

test "marker strict option enforces strict behavior without route strict mode" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "marker-strict",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/flags", strictMarkerBoolHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var strict_fail = try client.get("/flags?active=1");
    defer strict_fail.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, strict_fail.status);
    try std.testing.expect(std.mem.indexOf(u8, strict_fail.body, "\"type\":\"strict_bool\"") != null);
}
