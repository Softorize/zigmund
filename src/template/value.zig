const std = @import("std");

/// A dynamic value type for the Jinja2-compatible template engine.
/// Supports strings, numbers, booleans, none, lists, maps, and pre-escaped safe strings.
pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    none,
    list: []const Value,
    map: Map,
    safe_string: []const u8,

    pub const Map = struct {
        keys: []const []const u8,
        values: []const Value,

        pub fn get(self: Map, key: []const u8) ?Value {
            for (self.keys, 0..) |k, i| {
                if (std.mem.eql(u8, k, key)) return self.values[i];
            }
            return null;
        }

        pub fn len(self: Map) usize {
            return self.keys.len;
        }
    };

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .string => |s| s.len > 0,
            .integer => |i| i != 0,
            .float => |f| f != 0.0,
            .boolean => |b| b,
            .none => false,
            .list => |l| l.len > 0,
            .map => |m| m.keys.len > 0,
            .safe_string => |s| s.len > 0,
        };
    }

    pub fn eql(self: Value, other: Value) bool {
        const self_tag: u4 = @intFromEnum(self);
        const other_tag: u4 = @intFromEnum(other);
        if (self_tag != other_tag) {
            // Allow int/float cross-comparison
            if ((self == .integer or self == .float) and (other == .integer or other == .float)) {
                return self.toFloat() == other.toFloat();
            }
            return false;
        }
        return switch (self) {
            .string => |s| std.mem.eql(u8, s, other.string),
            .integer => |i| i == other.integer,
            .float => |f| f == other.float,
            .boolean => |b| b == other.boolean,
            .none => true,
            .safe_string => |s| std.mem.eql(u8, s, other.safe_string),
            .list, .map => false, // structural equality not supported
        };
    }

    pub fn toFloat(self: Value) f64 {
        return switch (self) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            .boolean => |b| if (b) 1.0 else 0.0,
            else => 0.0,
        };
    }

    pub fn toInteger(self: Value) ?i64 {
        return switch (self) {
            .integer => |i| i,
            .float => |f| @intFromFloat(f),
            .boolean => |b| if (b) @as(i64, 1) else 0,
            else => null,
        };
    }

    pub fn toString(self: Value, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        return switch (self) {
            .string => |s| try allocator.dupe(u8, s),
            .safe_string => |s| try allocator.dupe(u8, s),
            .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float => |f| try formatFloat(allocator, f),
            .boolean => |b| try allocator.dupe(u8, if (b) "True" else "False"),
            .none => try allocator.dupe(u8, ""),
            .list => |l| try formatList(allocator, l),
            .map => try allocator.dupe(u8, "{...}"),
        };
    }

    pub fn length(self: Value) ?usize {
        return switch (self) {
            .string => |s| s.len,
            .safe_string => |s| s.len,
            .list => |l| l.len,
            .map => |m| m.keys.len,
            else => null,
        };
    }

    /// Resolve dot access, e.g. `value.field` or `value.0`
    pub fn getAttr(self: Value, key: []const u8) ?Value {
        return switch (self) {
            .map => |m| m.get(key),
            .list => |l| {
                const idx = std.fmt.parseInt(usize, key, 10) catch return null;
                if (idx < l.len) return l[idx];
                return null;
            },
            else => null,
        };
    }

    /// Resolve subscript access, e.g. `value[index]`
    pub fn getItem(self: Value, index: Value) ?Value {
        return switch (self) {
            .list => |l| {
                const idx = index.toInteger() orelse return null;
                if (idx < 0) {
                    const uidx = l.len -| @as(usize, @intCast(-idx));
                    if (uidx < l.len) return l[uidx];
                    return null;
                }
                const uidx: usize = @intCast(idx);
                if (uidx < l.len) return l[uidx];
                return null;
            },
            .map => |m| {
                const key = switch (index) {
                    .string => |s| s,
                    else => return null,
                };
                return m.get(key);
            },
            else => null,
        };
    }
};

fn formatFloat(allocator: std.mem.Allocator, f: f64) ![]u8 {
    // Check if it's a whole number
    if (f == @trunc(f) and !std.math.isInf(f) and !std.math.isNan(f)) {
        return std.fmt.allocPrint(allocator, "{d}.0", .{@as(i64, @intFromFloat(f))});
    }
    return std.fmt.allocPrint(allocator, "{d}", .{f});
}

fn formatList(allocator: std.mem.Allocator, items: []const Value) std.mem.Allocator.Error![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (items, 0..) |item, i| {
        if (i > 0) try buf.appendSlice(allocator, ", ");
        const s = try item.toString(allocator);
        defer allocator.free(s);
        if (item == .string or item == .safe_string) {
            try buf.append(allocator, '\'');
            try buf.appendSlice(allocator, s);
            try buf.append(allocator, '\'');
        } else {
            try buf.appendSlice(allocator, s);
        }
    }
    try buf.append(allocator, ']');
    return buf.toOwnedSlice(allocator);
}

/// Context: a stack of variable scopes for template rendering.
pub const Context = struct {
    scopes: std.ArrayList(Scope),
    allocator: std.mem.Allocator,

    const Scope = std.StringHashMap(Value);

    pub fn init(allocator: std.mem.Allocator) Context {
        var scopes: std.ArrayList(Scope) = .empty;
        // Push initial global scope
        scopes.append(allocator, Scope.init(allocator)) catch {};
        return .{
            .scopes = scopes,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Context) void {
        for (self.scopes.items) |*scope| scope.deinit();
        self.scopes.deinit(self.allocator);
    }

    pub fn get(self: *const Context, name: []const u8) ?Value {
        // Search from top of scope stack down
        var i = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.scopes.items[i].get(name)) |val| return val;
        }
        return null;
    }

    pub fn set(self: *Context, name: []const u8, val: Value) !void {
        const top = &self.scopes.items[self.scopes.items.len - 1];
        try top.put(name, val);
    }

    pub fn pushScope(self: *Context) !void {
        try self.scopes.append(self.allocator, Scope.init(self.allocator));
    }

    pub fn popScope(self: *Context) void {
        if (self.scopes.items.len > 1) {
            var scope = self.scopes.pop() orelse return;
            scope.deinit();
        }
    }
};

// ─── Tests ─────────────────────────────────────────────────────────────

test "Value truthiness" {
    try std.testing.expect((Value{ .string = "hello" }).isTruthy());
    try std.testing.expect(!(Value{ .string = "" }).isTruthy());
    try std.testing.expect((Value{ .integer = 1 }).isTruthy());
    try std.testing.expect(!(Value{ .integer = 0 }).isTruthy());
    try std.testing.expect((Value{ .boolean = true }).isTruthy());
    try std.testing.expect(!(Value{ .boolean = false }).isTruthy());
    try std.testing.expect(!(Value.none).isTruthy());
}

test "Value toString" {
    const alloc = std.testing.allocator;
    {
        const s = try (Value{ .integer = 42 }).toString(alloc);
        defer alloc.free(s);
        try std.testing.expectEqualStrings("42", s);
    }
    {
        const s = try (Value{ .boolean = true }).toString(alloc);
        defer alloc.free(s);
        try std.testing.expectEqualStrings("True", s);
    }
    {
        const s = try (Value{ .float = 3.0 }).toString(alloc);
        defer alloc.free(s);
        try std.testing.expectEqualStrings("3.0", s);
    }
}

test "Value equality and cross-type comparison" {
    try std.testing.expect((Value{ .integer = 5 }).eql(Value{ .integer = 5 }));
    try std.testing.expect(!(Value{ .integer = 5 }).eql(Value{ .integer = 6 }));
    try std.testing.expect((Value{ .integer = 3 }).eql(Value{ .float = 3.0 }));
    try std.testing.expect((Value{ .string = "hi" }).eql(Value{ .string = "hi" }));
}

test "Value dot access and subscript" {
    const keys = [_][]const u8{ "name", "age" };
    const vals = [_]Value{ .{ .string = "Alice" }, .{ .integer = 30 } };
    const map = Value{ .map = .{ .keys = &keys, .values = &vals } };
    const name = map.getAttr("name").?;
    try std.testing.expect(name.eql(Value{ .string = "Alice" }));

    const items = [_]Value{ .{ .integer = 10 }, .{ .integer = 20 } };
    const list = Value{ .list = &items };
    const first = list.getAttr("0").?;
    try std.testing.expect(first.eql(Value{ .integer = 10 }));

    // Subscript
    const by_key = map.getItem(Value{ .string = "age" }).?;
    try std.testing.expect(by_key.eql(Value{ .integer = 30 }));
}

test "Context scope stack" {
    const alloc = std.testing.allocator;
    var ctx = Context.init(alloc);
    defer ctx.deinit();

    try ctx.set("x", Value{ .integer = 1 });
    try std.testing.expect(ctx.get("x").?.eql(Value{ .integer = 1 }));

    try ctx.pushScope();
    try ctx.set("x", Value{ .integer = 2 });
    try std.testing.expect(ctx.get("x").?.eql(Value{ .integer = 2 }));

    ctx.popScope();
    try std.testing.expect(ctx.get("x").?.eql(Value{ .integer = 1 }));
}
