const std = @import("std");
const zigmund = @import("zigmund");

const UserOut = struct {
    first_name: []const u8,
    last_name: []const u8,
    age: u32,

    pub const zigmund_computed_fields: []const zigmund.ComputedFieldEntry = &.{
        .{ .name = "full_name", .compute = computeFullName },
        .{ .name = "is_adult", .compute = computeIsAdult },
    };

    fn computeFullName(object: std.json.ObjectMap, allocator: std.mem.Allocator) !std.json.Value {
        const first = if (object.get("first_name")) |v| switch (v) {
            .string => |s| s,
            else => "",
        } else "";
        const last = if (object.get("last_name")) |v| switch (v) {
            .string => |s| s,
            else => "",
        } else "";
        const full = try std.fmt.allocPrint(allocator, "{s} {s}", .{ first, last });
        return .{ .string = full };
    }

    fn computeIsAdult(object: std.json.ObjectMap, _: std.mem.Allocator) !std.json.Value {
        const age: i64 = if (object.get("age")) |v| switch (v) {
            .integer => |n| n,
            else => 0,
        } else 0;
        return .{ .bool = age >= 18 };
    }
};

const MinimalComputed = struct {
    value: u32,

    pub const zigmund_computed_fields: []const zigmund.ComputedFieldEntry = &.{
        .{ .name = "doubled", .compute = computeDoubled },
    };

    fn computeDoubled(object: std.json.ObjectMap, _: std.mem.Allocator) !std.json.Value {
        const val: i64 = if (object.get("value")) |v| switch (v) {
            .integer => |n| n,
            else => 0,
        } else 0;
        return .{ .integer = val * 2 };
    }
};

const ExcludeAwareModel = struct {
    x: u32,
    y: u32,

    pub const zigmund_computed_fields: []const zigmund.ComputedFieldEntry = &.{
        .{ .name = "sum", .compute = computeSum },
    };

    fn computeSum(object: std.json.ObjectMap, _: std.mem.Allocator) !std.json.Value {
        const x: i64 = if (object.get("x")) |v| switch (v) {
            .integer => |n| n,
            else => 0,
        } else 0;
        const y: i64 = if (object.get("y")) |v| switch (v) {
            .integer => |n| n,
            else => 0,
        } else 0;
        return .{ .integer = x + y };
    }
};

const NoComputedModel = struct {
    name: []const u8,
    count: u32,
};

fn userHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .first_name = "Alice",
        .last_name = "Smith",
        .age = @as(u32, 25),
    });
}

fn minimalHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .value = @as(u32, 7),
    });
}

fn excludeAwareHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .x = @as(u32, 3),
        .y = @as(u32, 5),
    });
}

fn noComputedHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .name = "test",
        .count = @as(u32, 42),
    });
}

fn childHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .first_name = "Bob",
        .last_name = "Jones",
        .age = @as(u32, 12),
    });
}

test "computed fields are added to response JSON" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "computed-fields-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/user", userHandler, .{
        .response_model = UserOut,
    });

    var res = try app.dispatchSynthetic(.GET, "/user", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    // Original fields must be present
    try std.testing.expect(root.get("first_name") != null);
    try std.testing.expect(root.get("last_name") != null);
    try std.testing.expect(root.get("age") != null);

    // Computed fields must be present
    const full_name = root.get("full_name") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Alice Smith", full_name.string);

    const is_adult = root.get("is_adult") orelse return error.TestUnexpectedResult;
    try std.testing.expect(is_adult.bool == true);
}

test "computed field produces correct boolean for non-adult" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "computed-fields-child",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/child", childHandler, .{
        .response_model = UserOut,
    });

    var res = try app.dispatchSynthetic(.GET, "/child", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const is_adult = root.get("is_adult") orelse return error.TestUnexpectedResult;
    try std.testing.expect(is_adult.bool == false);
}

test "computed fields with integer arithmetic" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "computed-fields-minimal",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/minimal", minimalHandler, .{
        .response_model = MinimalComputed,
    });

    var res = try app.dispatchSynthetic(.GET, "/minimal", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const doubled = root.get("doubled") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i64, 14), doubled.integer);
}

test "computed fields are applied after include/exclude" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "computed-fields-exclude",
        .version = "0.0.1",
    });
    defer app.deinit();

    // y is excluded before computed fields run, so sum sees x but not y
    try app.get("/sum", excludeAwareHandler, .{
        .response_model = ExcludeAwareModel,
        .response_model_exclude = &.{"y"},
    });

    var res = try app.dispatchSynthetic(.GET, "/sum", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    // x must be present
    try std.testing.expect(root.get("x") != null);
    // y must be excluded
    try std.testing.expect(root.get("y") == null);
    // computed "sum" is present but y defaulted to 0 since it was excluded
    const sum = root.get("sum") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i64, 3), sum.integer);
}

test "computed fields appear alongside all struct fields when no exclusions" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "computed-fields-no-exclude",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/sum-all", excludeAwareHandler, .{
        .response_model = ExcludeAwareModel,
    });

    var res = try app.dispatchSynthetic(.GET, "/sum-all", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.get("x") != null);
    try std.testing.expect(root.get("y") != null);
    const sum = root.get("sum") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i64, 8), sum.integer);
}

test "response model without computed fields works normally" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "no-computed-fields",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.get("/plain", noComputedHandler, .{
        .response_model = NoComputedModel,
    });

    var res = try app.dispatchSynthetic(.GET, "/plain", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, res.body, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.get("name") != null);
    try std.testing.expect(root.get("count") != null);
}
