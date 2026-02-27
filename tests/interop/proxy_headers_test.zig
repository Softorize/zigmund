const std = @import("std");
const zigmund = @import("zigmund");

test "proxy extraction handles missing forwarded headers" {
    var req = try zigmund.Request.initSynthetic(std.testing.allocator, .GET, "/", "");
    defer req.deinit();

    const info = zigmund.runtime.extractProxyInfo(&req);
    try std.testing.expect(info.client_ip == null);
    try std.testing.expect(info.proto == null);
}

test "proxy extraction can be disabled by server config" {
    const headers = [_]std.http.Header{
        .{ .name = "x-forwarded-for", .value = "203.0.113.1" },
        .{ .name = "x-forwarded-proto", .value = "https" },
    };

    var req = try zigmund.Request.initSyntheticWithHeaders(std.testing.allocator, .GET, "/", "", &headers);
    defer req.deinit();

    const disabled = zigmund.runtime.extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = false,
    });
    try std.testing.expect(disabled.client_ip == null);
    try std.testing.expect(disabled.proto == null);

    const enabled = zigmund.runtime.extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = true,
    });
    try std.testing.expectEqualStrings("203.0.113.1", enabled.client_ip.?);
    try std.testing.expectEqualStrings("https", enabled.proto.?);
}

test "proxy extraction enforces trusted proxy cidr allowlist" {
    const headers = [_]std.http.Header{
        .{ .name = "x-forwarded-for", .value = "203.0.113.9, 198.51.100.44" },
        .{ .name = "x-forwarded-proto", .value = "https" },
    };

    var req = try zigmund.Request.initSyntheticWithHeaders(std.testing.allocator, .GET, "/", "", &headers);
    defer req.deinit();
    req.setPeerAddress(std.net.Address.initIp4(.{ 198, 51, 100, 44 }, 18080));

    const denied = zigmund.runtime.extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = true,
        .trusted_proxy_cidrs = &.{"10.0.0.0/8"},
    });
    try std.testing.expect(denied.client_ip == null);
    try std.testing.expect(denied.proto == null);

    const allowed = zigmund.runtime.extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = true,
        .trusted_proxy_cidrs = &.{"198.51.100.0/24"},
    });
    try std.testing.expectEqualStrings("203.0.113.9", allowed.client_ip.?);
    try std.testing.expectEqualStrings("https", allowed.proto.?);
}

test "proxy extraction supports ipv6 trusted proxy cidr allowlist" {
    const headers = [_]std.http.Header{
        .{ .name = "x-forwarded-for", .value = "2001:db8::9, 2001:db8::44" },
        .{ .name = "x-forwarded-proto", .value = "https" },
    };

    var req = try zigmund.Request.initSyntheticWithHeaders(std.testing.allocator, .GET, "/", "", &headers);
    defer req.deinit();
    req.setPeerAddress(try std.net.Address.parseIp("2001:db8::44", 18080));

    const denied = zigmund.runtime.extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = true,
        .trusted_proxy_cidrs = &.{"2001:db9::/64"},
    });
    try std.testing.expect(denied.client_ip == null);
    try std.testing.expect(denied.proto == null);

    const allowed = zigmund.runtime.extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = true,
        .trusted_proxy_cidrs = &.{"2001:db8::/64"},
    });
    try std.testing.expectEqualStrings("2001:db8::9", allowed.client_ip.?);
    try std.testing.expectEqualStrings("https", allowed.proto.?);
}

test "proxy extraction supports RFC forwarded header fields" {
    const headers = [_]std.http.Header{
        .{ .name = "forwarded", .value = "for=203.0.113.9;proto=https, for=198.51.100.44;proto=http" },
    };

    var req = try zigmund.Request.initSyntheticWithHeaders(std.testing.allocator, .GET, "/", "", &headers);
    defer req.deinit();

    const info = zigmund.runtime.extractProxyInfo(&req);
    try std.testing.expectEqualStrings("203.0.113.9", info.client_ip.?);
    try std.testing.expectEqualStrings("https", info.proto.?);
}

test "proxy extraction applies trust policy to forwarded headers" {
    const headers = [_]std.http.Header{
        .{ .name = "forwarded", .value = "for=203.0.113.9;proto=https" },
    };

    var req = try zigmund.Request.initSyntheticWithHeaders(std.testing.allocator, .GET, "/", "", &headers);
    defer req.deinit();
    req.setPeerAddress(std.net.Address.initIp4(.{ 198, 51, 100, 44 }, 18080));

    const denied = zigmund.runtime.extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = true,
        .trusted_proxy_cidrs = &.{"10.0.0.0/8"},
    });
    try std.testing.expect(denied.client_ip == null);
    try std.testing.expect(denied.proto == null);

    const allowed = zigmund.runtime.extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = true,
        .trusted_proxy_cidrs = &.{"198.51.100.0/24"},
    });
    try std.testing.expectEqualStrings("203.0.113.9", allowed.client_ip.?);
    try std.testing.expectEqualStrings("https", allowed.proto.?);
}
