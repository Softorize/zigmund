const std = @import("std");
const Value = @import("value.zig").Value;

pub const FilterFn = *const fn (Value, []const Value, std.mem.Allocator) anyerror!Value;

pub const FilterRegistry = struct {
    builtin: std.StaticStringMap(FilterFn),
    custom: std.StringHashMap(FilterFn),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FilterRegistry {
        return .{
            .builtin = builtinFilters(),
            .custom = std.StringHashMap(FilterFn).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FilterRegistry) void {
        self.custom.deinit();
    }

    pub fn get(self: *const FilterRegistry, name: []const u8) ?FilterFn {
        if (self.custom.get(name)) |f| return f;
        return self.builtin.get(name);
    }

    pub fn register(self: *FilterRegistry, name: []const u8, func: FilterFn) !void {
        try self.custom.put(name, func);
    }
};

fn builtinFilters() std.StaticStringMap(FilterFn) {
    return std.StaticStringMap(FilterFn).initComptime(.{
        .{ "upper", &filterUpper },
        .{ "lower", &filterLower },
        .{ "capitalize", &filterCapitalize },
        .{ "title", &filterTitle },
        .{ "trim", &filterTrim },
        .{ "default", &filterDefault },
        .{ "d", &filterDefault },
        .{ "length", &filterLength },
        .{ "count", &filterLength },
        .{ "join", &filterJoin },
        .{ "escape", &filterEscape },
        .{ "e", &filterEscape },
        .{ "safe", &filterSafe },
        .{ "replace", &filterReplace },
        .{ "truncate", &filterTruncate },
        .{ "first", &filterFirst },
        .{ "last", &filterLast },
        .{ "sort", &filterSort },
        .{ "reverse", &filterReverse },
        .{ "int", &filterInt },
        .{ "float", &filterFloat },
        .{ "string", &filterString },
        .{ "tojson", &filterToJson },
        .{ "list", &filterList },
        .{ "abs", &filterAbs },
        .{ "batch", &filterBatch },
        .{ "striptags", &filterStriptags },
        .{ "wordcount", &filterWordcount },
        .{ "center", &filterCenter },
    });
}

// ─── Built-in filters ──────────────────────────────────────────────────

fn filterUpper(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    const buf = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    return Value{ .safe_string = buf };
}

fn filterLower(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    const buf = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return Value{ .safe_string = buf };
}

fn filterCapitalize(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    if (s.len == 0) return val;
    const buf = try allocator.alloc(u8, s.len);
    buf[0] = std.ascii.toUpper(s[0]);
    for (s[1..], 0..) |c, i| buf[i + 1] = std.ascii.toLower(c);
    return Value{ .safe_string = buf };
}

fn filterTitle(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    if (s.len == 0) return val;
    const buf = try allocator.alloc(u8, s.len);
    var capitalize_next = true;
    for (s, 0..) |c, i| {
        if (c == ' ' or c == '\t' or c == '\n') {
            buf[i] = c;
            capitalize_next = true;
        } else if (capitalize_next) {
            buf[i] = std.ascii.toUpper(c);
            capitalize_next = false;
        } else {
            buf[i] = std.ascii.toLower(c);
        }
    }
    return Value{ .safe_string = buf };
}

fn filterTrim(val: Value, _: []const Value, _: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    return Value{ .string = trimmed };
}

fn filterDefault(val: Value, args: []const Value, _: std.mem.Allocator) !Value {
    if (val == .none or (val == .string and val.string.len == 0)) {
        if (args.len > 0) return args[0];
        return Value{ .string = "" };
    }
    return val;
}

fn filterLength(val: Value, _: []const Value, _: std.mem.Allocator) !Value {
    if (val.length()) |l| return Value{ .integer = @intCast(l) };
    return Value{ .integer = 0 };
}

fn filterJoin(val: Value, args: []const Value, allocator: std.mem.Allocator) !Value {
    const items = switch (val) {
        .list => |l| l,
        else => return val,
    };
    const sep = if (args.len > 0) switch (args[0]) {
        .string => |s| s,
        else => "",
    } else "";

    var buf: std.ArrayList(u8) = .empty;
    for (items, 0..) |item, i| {
        if (i > 0) try buf.appendSlice(allocator, sep);
        const s = try item.toString(allocator);
        defer allocator.free(s);
        try buf.appendSlice(allocator, s);
    }
    return Value{ .safe_string = try buf.toOwnedSlice(allocator) };
}

fn filterEscape(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => return val, // already safe
        else => return val,
    };
    const escaped = try htmlEscape(allocator, s);
    return Value{ .safe_string = escaped };
}

fn filterSafe(val: Value, _: []const Value, _: std.mem.Allocator) !Value {
    return switch (val) {
        .string => |s| Value{ .safe_string = s },
        else => val,
    };
}

fn filterReplace(val: Value, args: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    if (args.len < 2) return val;
    const old = switch (args[0]) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    const new = switch (args[1]) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    const result = try replaceAlloc(allocator, s, old, new);
    return Value{ .safe_string = result };
}

fn filterTruncate(val: Value, args: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    const max_len: usize = if (args.len > 0) @intCast(args[0].toInteger() orelse 255) else 255;
    if (s.len <= max_len) return val;
    const result = try std.fmt.allocPrint(allocator, "{s}...", .{s[0..max_len]});
    return Value{ .safe_string = result };
}

fn filterFirst(val: Value, _: []const Value, _: std.mem.Allocator) !Value {
    return switch (val) {
        .list => |l| if (l.len > 0) l[0] else Value.none,
        else => val,
    };
}

fn filterLast(val: Value, _: []const Value, _: std.mem.Allocator) !Value {
    return switch (val) {
        .list => |l| if (l.len > 0) l[l.len - 1] else Value.none,
        else => val,
    };
}

fn filterSort(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const items = switch (val) {
        .list => |l| l,
        else => return val,
    };
    if (items.len == 0) return val;
    const sorted = try allocator.dupe(Value, items);
    std.mem.sort(Value, sorted, {}, struct {
        fn lessThan(_: void, a: Value, b: Value) bool {
            const af = a.toFloat();
            const bf = b.toFloat();
            return af < bf;
        }
    }.lessThan);
    return Value{ .list = sorted };
}

fn filterReverse(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    switch (val) {
        .list => |l| {
            if (l.len == 0) return val;
            const reversed = try allocator.alloc(Value, l.len);
            for (l, 0..) |item, i| reversed[l.len - 1 - i] = item;
            return Value{ .list = reversed };
        },
        .string => |s| {
            if (s.len == 0) return val;
            const buf = try allocator.alloc(u8, s.len);
            for (s, 0..) |c, i| buf[s.len - 1 - i] = c;
            return Value{ .string = buf };
        },
        else => return val,
    }
}

fn filterInt(val: Value, _: []const Value, _: std.mem.Allocator) !Value {
    return switch (val) {
        .integer => val,
        .float => |f| Value{ .integer = @intFromFloat(f) },
        .boolean => |b| Value{ .integer = if (b) 1 else 0 },
        .string => |s| Value{ .integer = std.fmt.parseInt(i64, s, 10) catch 0 },
        else => Value{ .integer = 0 },
    };
}

fn filterFloat(val: Value, _: []const Value, _: std.mem.Allocator) !Value {
    return switch (val) {
        .float => val,
        .integer => |i| Value{ .float = @floatFromInt(i) },
        .boolean => |b| Value{ .float = if (b) 1.0 else 0.0 },
        .string => |s| Value{ .float = std.fmt.parseFloat(f64, s) catch 0.0 },
        else => Value{ .float = 0.0 },
    };
}

fn filterString(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const s = try val.toString(allocator);
    return Value{ .safe_string = s };
}

fn filterToJson(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const s = try valueToJson(allocator, val);
    return Value{ .safe_string = s };
}

fn filterList(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .list => return val,
        else => return val,
    };
    const chars = try allocator.alloc(Value, s.len);
    for (s, 0..) |c, i| {
        const ch = try allocator.alloc(u8, 1);
        ch[0] = c;
        chars[i] = Value{ .string = ch };
    }
    return Value{ .list = chars };
}

fn filterAbs(val: Value, _: []const Value, _: std.mem.Allocator) !Value {
    return switch (val) {
        .integer => |i| Value{ .integer = if (i < 0) -i else i },
        .float => |f| Value{ .float = @abs(f) },
        else => val,
    };
}

fn filterBatch(val: Value, args: []const Value, allocator: std.mem.Allocator) !Value {
    const items = switch (val) {
        .list => |l| l,
        else => return val,
    };
    const size: usize = if (args.len > 0) @intCast(args[0].toInteger() orelse 1) else 1;
    if (size == 0) return val;

    const num_batches = (items.len + size - 1) / size;
    const batches = try allocator.alloc(Value, num_batches);
    for (0..num_batches) |i| {
        const start = i * size;
        const end = @min(start + size, items.len);
        batches[i] = Value{ .list = items[start..end] };
    }
    return Value{ .list = batches };
}

fn filterStriptags(val: Value, _: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    var buf: std.ArrayList(u8) = .empty;
    var in_tag = false;
    for (s) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            try buf.append(allocator, c);
        }
    }
    return Value{ .safe_string = try buf.toOwnedSlice(allocator) };
}

fn filterWordcount(val: Value, _: []const Value, _: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return Value{ .integer = 0 },
    };
    var count: i64 = 0;
    var in_word = false;
    for (s) |c| {
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            count += 1;
        }
    }
    return Value{ .integer = count };
}

fn filterCenter(val: Value, args: []const Value, allocator: std.mem.Allocator) !Value {
    const s = switch (val) {
        .string => |v| v,
        .safe_string => |v| v,
        else => return val,
    };
    const width: usize = if (args.len > 0) @intCast(args[0].toInteger() orelse 80) else 80;
    if (s.len >= width) return val;
    const total_pad = width - s.len;
    const left_pad = total_pad / 2;
    const right_pad = total_pad - left_pad;
    const buf = try allocator.alloc(u8, width);
    @memset(buf[0..left_pad], ' ');
    @memcpy(buf[left_pad .. left_pad + s.len], s);
    @memset(buf[left_pad + s.len .. left_pad + s.len + right_pad], ' ');
    return Value{ .safe_string = buf };
}

// ─── Helpers ───────────────────────────────────────────────────────────

pub fn htmlEscape(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (s) |c| {
        switch (c) {
            '&' => try buf.appendSlice(allocator, "&amp;"),
            '<' => try buf.appendSlice(allocator, "&lt;"),
            '>' => try buf.appendSlice(allocator, "&gt;"),
            '"' => try buf.appendSlice(allocator, "&#34;"),
            '\'' => try buf.appendSlice(allocator, "&#39;"),
            else => try buf.append(allocator, c),
        }
    }
    return buf.toOwnedSlice(allocator);
}

fn replaceAlloc(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, input);
    var buf: std.ArrayList(u8) = .empty;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, cursor, needle)) |pos| {
        try buf.appendSlice(allocator, input[cursor..pos]);
        try buf.appendSlice(allocator, replacement);
        cursor = pos + needle.len;
    }
    try buf.appendSlice(allocator, input[cursor..]);
    return buf.toOwnedSlice(allocator);
}

fn valueToJson(allocator: std.mem.Allocator, val: Value) ![]u8 {
    return switch (val) {
        .string => |s| std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .safe_string => |s| std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .integer => |i| std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| std.fmt.allocPrint(allocator, "{d}", .{f}),
        .boolean => |b| allocator.dupe(u8, if (b) "true" else "false"),
        .none => allocator.dupe(u8, "null"),
        .list => |l| {
            var buf: std.ArrayList(u8) = .empty;
            try buf.append(allocator, '[');
            for (l, 0..) |item, i| {
                if (i > 0) try buf.appendSlice(allocator, ", ");
                const s = try valueToJson(allocator, item);
                defer allocator.free(s);
                try buf.appendSlice(allocator, s);
            }
            try buf.append(allocator, ']');
            return buf.toOwnedSlice(allocator);
        },
        .map => |m| {
            var buf: std.ArrayList(u8) = .empty;
            try buf.append(allocator, '{');
            for (m.keys, 0..) |key, i| {
                if (i > 0) try buf.appendSlice(allocator, ", ");
                try buf.appendSlice(allocator, "\"");
                try buf.appendSlice(allocator, key);
                try buf.appendSlice(allocator, "\": ");
                const s = try valueToJson(allocator, m.values[i]);
                defer allocator.free(s);
                try buf.appendSlice(allocator, s);
            }
            try buf.append(allocator, '}');
            return buf.toOwnedSlice(allocator);
        },
    };
}

// ─── Tests ─────────────────────────────────────────────────────────────

test "filter upper" {
    const alloc = std.testing.allocator;
    var reg = FilterRegistry.init(alloc);
    defer reg.deinit();

    const f = reg.get("upper").?;
    const result = try f(Value{ .string = "hello" }, &.{}, alloc);
    const s = try result.toString(alloc);
    defer alloc.free(s);
    try std.testing.expectEqualStrings("HELLO", s);
}

test "filter default" {
    const alloc = std.testing.allocator;
    var reg = FilterRegistry.init(alloc);
    defer reg.deinit();

    const f = reg.get("default").?;
    const result = try f(Value.none, &.{Value{ .string = "fallback" }}, alloc);
    const s = try result.toString(alloc);
    defer alloc.free(s);
    try std.testing.expectEqualStrings("fallback", s);
}

test "filter join" {
    const alloc = std.testing.allocator;
    var reg = FilterRegistry.init(alloc);
    defer reg.deinit();

    const items = [_]Value{ .{ .string = "a" }, .{ .string = "b" }, .{ .string = "c" } };
    const f = reg.get("join").?;
    const result = try f(Value{ .list = &items }, &.{Value{ .string = ", " }}, alloc);
    const s = try result.toString(alloc);
    defer alloc.free(s);
    try std.testing.expectEqualStrings("a, b, c", s);
}

test "filter escape" {
    const alloc = std.testing.allocator;
    const escaped = try htmlEscape(alloc, "<b>hello</b>");
    defer alloc.free(escaped);
    try std.testing.expectEqualStrings("&lt;b&gt;hello&lt;/b&gt;", escaped);
}

test "filter length" {
    const alloc = std.testing.allocator;
    var reg = FilterRegistry.init(alloc);
    defer reg.deinit();

    const items = [_]Value{ .{ .integer = 1 }, .{ .integer = 2 } };
    const f = reg.get("length").?;
    const result = try f(Value{ .list = &items }, &.{}, alloc);
    try std.testing.expect(result.eql(Value{ .integer = 2 }));
}

test "custom filter registration" {
    const alloc = std.testing.allocator;
    var reg = FilterRegistry.init(alloc);
    defer reg.deinit();

    const myFilter = struct {
        fn call(_: Value, _: []const Value, _: std.mem.Allocator) !Value {
            return Value{ .string = "custom" };
        }
    }.call;

    try reg.register("my_filter", &myFilter);
    const f = reg.get("my_filter").?;
    const result = try f(Value.none, &.{}, alloc);
    try std.testing.expectEqualStrings("custom", result.string);
}
