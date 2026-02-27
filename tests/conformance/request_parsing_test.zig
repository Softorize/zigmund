const std = @import("std");
const zigmund = @import("zigmund");

test "typed request parsing helpers" {
    var req = try zigmund.Request.initSynthetic(
        std.testing.allocator,
        .POST,
        "/items/5?page=2&active=true",
        "{\"name\":\"zig\",\"count\":2}",
    );
    defer req.deinit();

    try req.setPathParam("item_id", "5");

    try std.testing.expectEqual(@as(i64, 2), try req.queryAs(i64, "page"));
    try std.testing.expectEqual(true, try req.queryAs(bool, "active"));
    try std.testing.expectEqual(@as(u32, 5), try req.paramAs(u32, "item_id"));

    const Body = struct {
        name: []const u8,
        count: u8,
    };

    var parsed = try req.bodyJson(Body);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("zig", parsed.value.name);
    try std.testing.expectEqual(@as(u8, 2), parsed.value.count);
}
