const std = @import("std");
const zigmund = @import("zigmund");

test "typed request parsing helpers" {
    var req = try zigmund.Request.initSynthetic(
        std.testing.allocator,
        .POST,
        "/items/5?page=2&active=true&next=https%3A%2F%2Fexample.com%2Fitems%3Fpage%3D3&ip=127.0.0.1&peer=%3A%3A1",
        "{\"name\":\"zig\",\"count\":2}",
    );
    defer req.deinit();

    try req.setPathParam("item_id", "5");

    try std.testing.expectEqual(@as(i64, 2), try req.queryAs(i64, "page"));
    try std.testing.expectEqual(true, try req.queryAs(bool, "active"));
    try std.testing.expectEqual(@as(u32, 5), try req.paramAs(u32, "item_id"));

    const next = try req.queryAs(std.Uri, "next");
    var host_buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("example.com", try next.getHost(&host_buf));

    const ip = try req.queryAs(std.net.Ip4Address, "ip");
    try std.testing.expectEqual(@as(u16, 0), ip.getPort());
    try std.testing.expectFmt("127.0.0.1:0", "{f}", .{ip});

    const peer = try req.queryAs(std.net.Ip6Address, "peer");
    try std.testing.expectEqual(@as(u16, 0), peer.getPort());
    try std.testing.expectFmt("[::1]:0", "{f}", .{peer});

    const Body = struct {
        name: []const u8,
        count: u8,
    };

    var parsed = try req.bodyJson(Body);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("zig", parsed.value.name);
    try std.testing.expectEqual(@as(u8, 2), parsed.value.count);
}
