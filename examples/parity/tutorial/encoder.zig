const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/encoder/";

const Priority = enum {
    low,
    medium,
    high,
};

const Address = struct {
    street: []const u8,
    city: []const u8,
    zip_code: ?[]const u8 = null,
};

const UserProfile = struct {
    id: u32,
    name: []const u8,
    email: ?[]const u8 = null,
    is_active: bool,
    score: f64,
    priority: Priority,
    address: Address,
    tags: []const []const u8,
};

fn getEncodedProfile(allocator: std.mem.Allocator) !zigmund.Response {
    const profile = UserProfile{
        .id = 42,
        .name = "Alice",
        .email = "alice@example.com",
        .is_active = true,
        .score = 98.5,
        .priority = .high,
        .address = .{
            .street = "123 Main St",
            .city = "Springfield",
            .zip_code = "62704",
        },
        .tags = &.{ "admin", "verified" },
    };
    return zigmund.Response.json(allocator, profile);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/encoder", getEncodedProfile, .{
        .summary = "JSON encoding of complex types (structs, enums, optionals)",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_encoder_profile",
    });
}
