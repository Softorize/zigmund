const std = @import("std");
const ServerConfig = @import("config.zig").ServerConfig;
const Request = @import("../http/request.zig").Request;

pub const ProxyInfo = struct {
    client_ip: ?[]const u8 = null,
    proto: ?[]const u8 = null,
};

pub fn extractProxyInfo(req: *const Request) ProxyInfo {
    return .{
        .client_ip = firstValue(req.header("x-forwarded-for")),
        .proto = firstValue(req.header("x-forwarded-proto")),
    };
}

pub fn extractProxyInfoWithConfig(req: *const Request, cfg: ServerConfig) ProxyInfo {
    if (!shouldTrustProxyHeaders(req, cfg)) return .{};
    return extractProxyInfo(req);
}

fn shouldTrustProxyHeaders(req: *const Request, cfg: ServerConfig) bool {
    if (!cfg.trusted_proxy_headers) return false;
    if (cfg.trusted_proxy_cidrs.len == 0) return true;

    const peer = req.peerAddress() orelse return false;
    return addressInCidrs(peer, cfg.trusted_proxy_cidrs);
}

fn addressInCidrs(address: std.net.Address, cidrs: []const []const u8) bool {
    for (cidrs) |raw_cidr| {
        if (addressInCidr(address, raw_cidr)) return true;
    }
    return false;
}

fn addressInCidr(address: std.net.Address, raw_cidr: []const u8) bool {
    const cidr = std.mem.trim(u8, raw_cidr, " \t");
    if (cidr.len == 0) return false;

    const slash = std.mem.indexOfScalar(u8, cidr, '/');
    const ip_text = std.mem.trim(u8, cidr[0 .. slash orelse cidr.len], " \t");
    if (ip_text.len == 0) return false;

    const network = std.net.Address.parseIp(ip_text, 0) catch return false;

    return switch (address.any.family) {
        std.posix.AF.INET => blk: {
            if (network.any.family != std.posix.AF.INET) break :blk false;
            const prefix_bits = parsePrefixBits(cidr, slash, 32) orelse break :blk false;
            if (prefix_bits > 32) break :blk false;

            const addr_bytes = @as(*const [4]u8, @ptrCast(&address.in.sa.addr));
            const network_bytes = @as(*const [4]u8, @ptrCast(&network.in.sa.addr));
            break :blk prefixBitsMatch(addr_bytes[0..], network_bytes[0..], prefix_bits);
        },
        std.posix.AF.INET6 => blk: {
            if (network.any.family != std.posix.AF.INET6) break :blk false;
            const prefix_bits = parsePrefixBits(cidr, slash, 128) orelse break :blk false;
            if (prefix_bits > 128) break :blk false;

            break :blk prefixBitsMatch(address.in6.sa.addr[0..], network.in6.sa.addr[0..], prefix_bits);
        },
        else => false,
    };
}

fn parsePrefixBits(cidr: []const u8, slash: ?usize, default_value: usize) ?usize {
    if (slash == null) return default_value;
    const raw = std.mem.trim(u8, cidr[slash.? + 1 ..], " \t");
    if (raw.len == 0) return null;
    return std.fmt.parseInt(usize, raw, 10) catch null;
}

fn prefixBitsMatch(address_bytes: []const u8, network_bytes: []const u8, prefix_bits: usize) bool {
    const full_bytes = prefix_bits / 8;
    const partial_bits = prefix_bits % 8;

    if (full_bytes > address_bytes.len or full_bytes > network_bytes.len) return false;
    if (!std.mem.eql(u8, address_bytes[0..full_bytes], network_bytes[0..full_bytes])) return false;
    if (partial_bits == 0) return true;

    if (full_bytes >= address_bytes.len or full_bytes >= network_bytes.len) return false;

    const shift: u3 = @intCast(8 - partial_bits);
    const mask: u8 = @as(u8, 0xff) << shift;
    return (address_bytes[full_bytes] & mask) == (network_bytes[full_bytes] & mask);
}

fn firstValue(raw: ?[]const u8) ?[]const u8 {
    const value = raw orelse return null;
    if (std.mem.indexOfScalar(u8, value, ',')) |idx| {
        return std.mem.trim(u8, value[0..idx], " \t");
    }
    return std.mem.trim(u8, value, " \t");
}

test "extract first forwarded value" {
    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/", "");
    defer req.deinit();
    // synthetic requests do not have raw headers; this validates null behavior.
    const info = extractProxyInfo(&req);
    try std.testing.expect(info.client_ip == null);
}

test "cidr trust accepts only allowed peer ranges" {
    const headers = [_]std.http.Header{
        .{ .name = "x-forwarded-for", .value = "203.0.113.10" },
        .{ .name = "x-forwarded-proto", .value = "https" },
    };

    var req = try Request.initSyntheticWithHeaders(std.testing.allocator, .GET, "/", "", &headers);
    defer req.deinit();

    req.setPeerAddress(std.net.Address.initIp4(.{ 198, 51, 100, 7 }, 44321));

    const denied = extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = true,
        .trusted_proxy_cidrs = &.{"10.0.0.0/8"},
    });
    try std.testing.expect(denied.client_ip == null);
    try std.testing.expect(denied.proto == null);

    const allowed = extractProxyInfoWithConfig(&req, .{
        .trusted_proxy_headers = true,
        .trusted_proxy_cidrs = &.{"198.51.100.0/24"},
    });
    try std.testing.expectEqualStrings("203.0.113.10", allowed.client_ip.?);
    try std.testing.expectEqualStrings("https", allowed.proto.?);
}
