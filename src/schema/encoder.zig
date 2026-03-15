const std = @import("std");

/// Converts complex Zig types to a JSON-serializable `std.json.Value` tree.
///
/// This is the Zig equivalent of FastAPI's `jsonable_encoder`. It recursively
/// walks the value and produces a `std.json.Value` that can be serialized to
/// JSON with the standard library.
///
/// Supported types:
///   - null
///   - optionals (encoded as inner value or .null)
///   - bool
///   - integers (all widths, cast to i64)
///   - floats (all widths, cast to f64)
///   - []const u8 (strings)
///   - slices (encoded as JSON arrays)
///   - structs (encoded as JSON objects)
///   - enums (encoded as their tag name string)
pub fn jsonableEncode(allocator: std.mem.Allocator, value: anytype) !std.json.Value {
    const T = @TypeOf(value);

    // Handle null
    if (T == @TypeOf(null)) return .null;

    // Handle optionals
    if (@typeInfo(T) == .optional) {
        if (value) |v| return jsonableEncode(allocator, v);
        return .null;
    }

    // Handle bool
    if (T == bool) return .{ .bool = value };

    // Handle integers
    if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return .{ .integer = @intCast(value) };
    }

    // Handle floats
    if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
        return .{ .float = @floatCast(value) };
    }

    // Handle strings ([]const u8)
    if (comptime isStringType(T)) {
        return .{ .string = value };
    }

    // Handle slices (non-string)
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
        var arr = std.json.Array.init(allocator);
        for (value) |item| {
            try arr.append(try jsonableEncode(allocator, item));
        }
        return .{ .array = arr };
    }

    // Handle structs
    if (@typeInfo(T) == .@"struct") {
        var obj = std.json.ObjectMap.init(allocator);
        inline for (std.meta.fields(T)) |field| {
            const fv = @field(value, field.name);
            try obj.put(field.name, try jsonableEncode(allocator, fv));
        }
        return .{ .object = obj };
    }

    // Handle enums
    if (@typeInfo(T) == .@"enum") {
        return .{ .string = @tagName(value) };
    }

    return .null;
}

fn isStringType(comptime T: type) bool {
    if (T == []const u8) return true;
    if (@typeInfo(T) == .pointer) {
        const info = @typeInfo(T).pointer;
        if (info.size == .slice and info.child == u8) return true;
        // Handle *const [N]u8 → coercible to []const u8
        if (info.size == .one) {
            if (@typeInfo(info.child) == .array) {
                const arr_info = @typeInfo(info.child).array;
                if (arr_info.child == u8) return true;
            }
        }
    }
    return false;
}

// ── Tests ───────────────────────────────────────────────────────────────

test "encode null" {
    const result = try jsonableEncode(std.testing.allocator, null);
    try std.testing.expectEqual(std.json.Value.null, result);
}

test "encode bool" {
    const t = try jsonableEncode(std.testing.allocator, true);
    try std.testing.expect(t.bool == true);

    const f = try jsonableEncode(std.testing.allocator, false);
    try std.testing.expect(f.bool == false);
}

test "encode integer" {
    const val = try jsonableEncode(std.testing.allocator, @as(i32, 42));
    try std.testing.expectEqual(@as(i64, 42), val.integer);
}

test "encode float" {
    const val = try jsonableEncode(std.testing.allocator, @as(f64, 3.14));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), val.float, 0.001);
}

test "encode string" {
    const val = try jsonableEncode(std.testing.allocator, @as([]const u8, "hello"));
    try std.testing.expectEqualStrings("hello", val.string);
}

test "encode optional with value" {
    const opt: ?i32 = 7;
    const val = try jsonableEncode(std.testing.allocator, opt);
    try std.testing.expectEqual(@as(i64, 7), val.integer);
}

test "encode optional null" {
    const opt: ?i32 = null;
    const val = try jsonableEncode(std.testing.allocator, opt);
    try std.testing.expectEqual(std.json.Value.null, val);
}

test "encode slice" {
    const items = [_]i32{ 1, 2, 3 };
    var val = try jsonableEncode(std.testing.allocator, @as([]const i32, &items));
    defer val.array.deinit();

    try std.testing.expectEqual(@as(usize, 3), val.array.items.len);
    try std.testing.expectEqual(@as(i64, 1), val.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 2), val.array.items[1].integer);
    try std.testing.expectEqual(@as(i64, 3), val.array.items[2].integer);
}

test "encode struct" {
    const S = struct {
        name: []const u8,
        age: i32,
        active: bool,
    };
    var val = try jsonableEncode(std.testing.allocator, S{
        .name = "alice",
        .age = 30,
        .active = true,
    });
    defer val.object.deinit();

    try std.testing.expectEqualStrings("alice", val.object.get("name").?.string);
    try std.testing.expectEqual(@as(i64, 30), val.object.get("age").?.integer);
    try std.testing.expect(val.object.get("active").?.bool == true);
}

test "encode enum" {
    const Color = enum { red, green, blue };
    const val = try jsonableEncode(std.testing.allocator, Color.green);
    try std.testing.expectEqualStrings("green", val.string);
}

test "encode nested struct" {
    const Inner = struct { x: i32 };
    const Outer = struct { inner: Inner, label: []const u8 };

    var val = try jsonableEncode(std.testing.allocator, Outer{
        .inner = .{ .x = 99 },
        .label = "test",
    });
    defer {
        val.object.get("inner").?.object.deinit();
        val.object.deinit();
    }

    const inner_obj = val.object.get("inner").?.object;
    try std.testing.expectEqual(@as(i64, 99), inner_obj.get("x").?.integer);
    try std.testing.expectEqualStrings("test", val.object.get("label").?.string);
}

test "encode struct with optional fields" {
    const S = struct {
        required: []const u8,
        maybe: ?i32,
    };
    var val = try jsonableEncode(std.testing.allocator, S{
        .required = "yes",
        .maybe = null,
    });
    defer val.object.deinit();

    try std.testing.expectEqualStrings("yes", val.object.get("required").?.string);
    try std.testing.expectEqual(std.json.Value.null, val.object.get("maybe").?);
}
