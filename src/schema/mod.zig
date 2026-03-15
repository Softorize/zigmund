const std = @import("std");

pub const encoder = @import("encoder.zig");
pub const jsonableEncode = encoder.jsonableEncode;

pub const extra_types = @import("extra_types.zig");
pub const Uuid = extra_types.Uuid;
pub const DateTime = extra_types.DateTime;
pub const Duration = extra_types.Duration;

pub fn schemaForType(comptime T: type, allocator: std.mem.Allocator) ![]u8 {
    return switch (@typeInfo(T)) {
        .bool => allocator.dupe(u8, "{\"type\":\"boolean\"}"),
        .int, .comptime_int => allocator.dupe(u8, "{\"type\":\"integer\"}"),
        .float, .comptime_float => allocator.dupe(u8, "{\"type\":\"number\"}"),
        .pointer => |info| {
            if (info.size == .slice and info.child == u8) {
                return allocator.dupe(u8, "{\"type\":\"string\"}");
            }
            return allocator.dupe(u8, "{\"type\":\"object\"}");
        },
        else => allocator.dupe(u8, "{\"type\":\"object\"}"),
    };
}

test "schema generation primitive" {
    const schema = try schemaForType(i64, std.testing.allocator);
    defer std.testing.allocator.free(schema);
    try std.testing.expectEqualStrings("{\"type\":\"integer\"}", schema);
}
