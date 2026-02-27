const std = @import("std");
const zigmund = @import("zigmund");

const ItemModel = struct {
    id: u32,
    name: []const u8,
    meta: ?[]const u8 = null,
    nested: struct {
        keep: []const u8,
        drop: ?[]const u8 = null,
    },
};

const DeepModel = struct {
    id: u32,
    profile: struct {
        name: []const u8,
        email: []const u8,
        internal: []const u8,
    },
};

const AliasDefaultsModel = struct {
    id: u32,
    name: []const u8,
    active: bool = true,
    note: ?[]const u8 = null,
    profile: struct {
        email: []const u8,
        flags: u8 = 0,
    },

    pub const zigmund_response_aliases: []const zigmund.ResponseModelAlias = &.{
        .{ .path = "name", .alias = "display_name" },
        .{ .path = "profile.email", .alias = "contact_email" },
    };
};

const UnsetModel = struct {
    id: u32,
    note: ?[]const u8 = null,
};

fn shapedHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .id = @as(u32, 7),
        .name = "widget",
        .meta = @as(?[]const u8, null),
        .nested = .{
            .keep = "yes",
            .drop = @as(?[]const u8, null),
        },
        .unused = "discard",
    });
}

fn deepShapedHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .id = @as(u32, 99),
        .profile = .{
            .name = "alice",
            .email = "alice@example.com",
            .internal = "drop-me",
        },
        .extra = "drop",
    });
}

fn aliasDefaultsHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .id = @as(u32, 11),
        .name = "alice",
        .active = true,
        .note = @as(?[]const u8, null),
        .profile = .{
            .email = "alice@example.com",
            .flags = @as(u8, 0),
            .unused = "drop-me",
        },
        .extra = "drop-me",
    });
}

fn unsetHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .id = @as(u32, 1),
        .note = @as(?[]const u8, null),
    });
}

test "response_model runtime shaping include/exclude/exclude_none" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-model-runtime",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/items", shapedHandler, .{
        .response_model = ItemModel,
        .response_model_include = &.{ "id", "name", "meta", "nested" },
        .response_model_exclude = &.{"meta"},
        .response_model_exclude_none = true,
    });

    var res = try app.dispatchSynthetic(.GET, "/items", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.get("id") != null);
    try std.testing.expect(root.get("name") != null);
    try std.testing.expect(root.get("meta") == null);
    try std.testing.expect(root.get("unused") == null);

    const nested_value = root.get("nested") orelse return error.TestUnexpectedResult;
    switch (nested_value) {
        .object => |nested| {
            try std.testing.expect(nested.get("keep") != null);
            try std.testing.expect(nested.get("drop") == null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "response_model runtime shaping supports deep include/exclude paths" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-model-runtime-deep",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/deep", deepShapedHandler, .{
        .response_model = DeepModel,
        .response_model_include = &.{ "id", "profile.name", "profile.email" },
        .response_model_exclude = &.{"profile.email"},
    });

    var res = try app.dispatchSynthetic(.GET, "/deep", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.get("id") != null);
    try std.testing.expect(root.get("extra") == null);

    const profile_value = root.get("profile") orelse return error.TestUnexpectedResult;
    switch (profile_value) {
        .object => |profile| {
            try std.testing.expect(profile.get("name") != null);
            try std.testing.expect(profile.get("email") == null);
            try std.testing.expect(profile.get("internal") == null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "response_model runtime shaping applies aliases and exclude_defaults" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-model-runtime-alias-defaults",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/alias-defaults", aliasDefaultsHandler, .{
        .response_model = AliasDefaultsModel,
        .response_model_exclude_defaults = true,
        .response_model_exclude_none = true,
    });

    var res = try app.dispatchSynthetic(.GET, "/alias-defaults", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.get("id") != null);
    try std.testing.expect(root.get("display_name") != null);
    try std.testing.expect(root.get("name") == null);
    try std.testing.expect(root.get("active") == null);
    try std.testing.expect(root.get("note") == null);
    try std.testing.expect(root.get("extra") == null);

    const profile_value = root.get("profile") orelse return error.TestUnexpectedResult;
    switch (profile_value) {
        .object => |profile| {
            try std.testing.expect(profile.get("contact_email") != null);
            try std.testing.expect(profile.get("email") == null);
            try std.testing.expect(profile.get("flags") == null);
            try std.testing.expect(profile.get("unused") == null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "response_model runtime shaping honors response_model_by_alias=false" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-model-runtime-no-alias",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/alias-off", aliasDefaultsHandler, .{
        .response_model = AliasDefaultsModel,
        .response_model_by_alias = false,
        .response_model_exclude_defaults = true,
        .response_model_exclude_none = true,
    });

    var res = try app.dispatchSynthetic(.GET, "/alias-off", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.get("name") != null);
    try std.testing.expect(root.get("display_name") == null);

    const profile_value = root.get("profile") orelse return error.TestUnexpectedResult;
    switch (profile_value) {
        .object => |profile| {
            try std.testing.expect(profile.get("email") != null);
            try std.testing.expect(profile.get("contact_email") == null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "response_model runtime shaping keeps explicit null when only exclude_unset is enabled" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "response-model-runtime-unset",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/unset", unsetHandler, .{
        .response_model = UnsetModel,
        .response_model_exclude_unset = true,
    });

    var res = try app.dispatchSynthetic(.GET, "/unset", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"note\":null") != null);
}
