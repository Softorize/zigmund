const std = @import("std");
const types = @import("types.zig");

pub fn needsResponseShaping(options: types.StoredRouteOptions) bool {
    if (options.response_model_transform != null) return true;
    if (options.response_model_validate != null) return true;
    if (options.response_model_field_rules.len != 0) return true;
    if (options.response_model_include.len != 0) return true;
    if (options.response_model_exclude.len != 0) return true;
    if (options.response_model_exclude_none) return true;
    if (options.response_model_exclude_unset) return true;
    if (options.response_model_exclude_defaults) return true;
    return false;
}

pub fn applyTopLevelIncludeExclude(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    include: []const []const u8,
    exclude: []const []const u8,
) !void {
    if (include.len == 0 and exclude.len == 0) return;

    var path_buf: std.ArrayList(u8) = .empty;
    defer path_buf.deinit(allocator);

    try applyIncludeExcludeRecursive(allocator, value, include, exclude, &path_buf);
}

pub fn applyResponseModelFieldFilter(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    rules: []const types.ResponseModelFieldRule,
) !void {
    if (rules.len == 0) return;

    const include_paths = try allocator.alloc([]const u8, rules.len);
    defer allocator.free(include_paths);

    for (rules, 0..) |rule, idx| {
        include_paths[idx] = rule.path;
    }
    try applyTopLevelIncludeExclude(allocator, value, include_paths, &.{});
}

pub fn applyExcludeDefaults(
    value: *std.json.Value,
    rules: []const types.ResponseModelFieldRule,
) !void {
    for (rules) |rule| {
        if (rule.default_value == .none) continue;
        try removePathIfDefault(value, rule.path, rule.default_value);
    }
}

pub fn removePathIfDefault(
    value: *std.json.Value,
    path: []const u8,
    default_value: types.ResponseModelDefaultValue,
) !void {
    if (path.len == 0) return;

    switch (value.*) {
        .object => |*object| {
            const split = splitPath(path);
            if (split.tail.len == 0) {
                const current = object.get(split.head) orelse return;
                if (jsonValueMatchesDefault(current, default_value)) {
                    _ = object.swapRemove(split.head);
                }
                return;
            }

            if (object.getPtr(split.head)) |child| {
                try removePathIfDefault(child, split.tail, default_value);
            }
        },
        .array => |*array| {
            for (array.items) |*item| {
                try removePathIfDefault(item, path, default_value);
            }
        },
        else => {},
    }
}

pub fn jsonValueMatchesDefault(value: std.json.Value, default_value: types.ResponseModelDefaultValue) bool {
    return switch (default_value) {
        .none => false,
        .null => value == .null,
        .bool => |expected| switch (value) {
            .bool => |actual| actual == expected,
            else => false,
        },
        .integer => |expected| switch (value) {
            .integer => |actual| actual == expected,
            .float => |actual| actual == @as(f64, @floatFromInt(expected)),
            .number_string => |actual| blk: {
                const parsed = std.fmt.parseInt(i64, actual, 10) catch break :blk false;
                break :blk parsed == expected;
            },
            else => false,
        },
        .float => |expected| switch (value) {
            .float => |actual| actual == expected,
            .integer => |actual| @as(f64, @floatFromInt(actual)) == expected,
            .number_string => |actual| blk: {
                const parsed = std.fmt.parseFloat(f64, actual) catch break :blk false;
                break :blk parsed == expected;
            },
            else => false,
        },
        .string => |expected| switch (value) {
            .string => |actual| std.mem.eql(u8, actual, expected),
            else => false,
        },
    };
}

pub fn applyResponseModelAliases(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    rules: []const types.ResponseModelFieldRule,
) !void {
    var max_depth: usize = 0;
    for (rules) |rule| {
        if (rule.alias == null) continue;
        max_depth = @max(max_depth, pathDepth(rule.path));
    }
    if (max_depth == 0) return;

    var depth = max_depth;
    while (depth > 0) : (depth -= 1) {
        for (rules) |rule| {
            const alias = rule.alias orelse continue;
            if (pathDepth(rule.path) != depth) continue;
            try renamePathField(allocator, value, rule.path, alias);
        }
    }
}

pub fn renamePathField(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    path: []const u8,
    alias: []const u8,
) !void {
    if (path.len == 0) return;

    switch (value.*) {
        .object => |*object| {
            const split = splitPath(path);
            if (split.tail.len == 0) {
                if (std.mem.eql(u8, split.head, alias)) return;

                const removed = object.fetchSwapRemove(split.head) orelse return;
                if (object.get(alias) == null) {
                    try object.put(alias, removed.value);
                }
                return;
            }

            if (object.getPtr(split.head)) |child| {
                try renamePathField(allocator, child, split.tail, alias);
            }
        },
        .array => |*array| {
            for (array.items) |*item| {
                try renamePathField(allocator, item, path, alias);
            }
        },
        else => {},
    }
}

pub fn splitPath(path: []const u8) struct { head: []const u8, tail: []const u8 } {
    const dot = std.mem.indexOfScalar(u8, path, '.') orelse {
        return .{ .head = path, .tail = "" };
    };
    return .{
        .head = path[0..dot],
        .tail = path[dot + 1 ..],
    };
}

pub fn pathDepth(path: []const u8) usize {
    if (path.len == 0) return 0;

    var depth: usize = 1;
    for (path) |ch| {
        if (ch == '.') depth += 1;
    }
    return depth;
}

pub fn applyIncludeExcludeRecursive(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    include: []const []const u8,
    exclude: []const []const u8,
    path_buf: *std.ArrayList(u8),
) !void {
    switch (value.*) {
        .object => |*object| {
            var remove_keys: std.ArrayList([]const u8) = .empty;
            defer remove_keys.deinit(allocator);

            var iter = object.iterator();
            while (iter.next()) |entry| {
                const restore_len = path_buf.items.len;
                if (restore_len != 0) try path_buf.append(allocator, '.');
                try path_buf.appendSlice(allocator, entry.key_ptr.*);
                const path = path_buf.items;

                const include_exact = pathInList(include, path);
                const include_child = pathHasChild(include, path);
                const include_match = include.len == 0 or include_exact or include_child;
                const exclude_exact = pathInList(exclude, path);
                const exclude_child = pathHasChild(exclude, path);

                if (!include_match or exclude_exact) {
                    try remove_keys.append(allocator, entry.key_ptr.*);
                    path_buf.items.len = restore_len;
                    continue;
                }

                if (include_child or exclude_child) {
                    try applyIncludeExcludeRecursive(allocator, entry.value_ptr, include, exclude, path_buf);
                }

                path_buf.items.len = restore_len;
            }

            for (remove_keys.items) |key| {
                _ = object.swapRemove(key);
            }
        },
        .array => |*array| {
            for (array.items) |*item| {
                try applyIncludeExcludeRecursive(allocator, item, include, exclude, path_buf);
            }
        },
        else => {},
    }
}

pub fn pruneNullValues(allocator: std.mem.Allocator, value: *std.json.Value) !void {
    switch (value.*) {
        .object => |*object| {
            var remove_keys: std.ArrayList([]const u8) = .empty;
            defer remove_keys.deinit(allocator);

            var iter = object.iterator();
            while (iter.next()) |entry| {
                try pruneNullValues(allocator, entry.value_ptr);
                if (entry.value_ptr.* == .null) {
                    try remove_keys.append(allocator, entry.key_ptr.*);
                }
            }

            for (remove_keys.items) |key| {
                _ = object.swapRemove(key);
            }
        },
        .array => |*array| {
            var idx: usize = 0;
            while (idx < array.items.len) : (idx += 1) {
                try pruneNullValues(allocator, &array.items[idx]);
            }

            var write_idx: usize = 0;
            for (array.items) |item| {
                if (item == .null) continue;
                array.items[write_idx] = item;
                write_idx += 1;
            }
            array.items.len = write_idx;
        },
        else => {},
    }
}

pub fn pathInList(list: []const []const u8, needle: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

pub fn pathHasChild(list: []const []const u8, path: []const u8) bool {
    if (path.len == 0) return list.len != 0;

    for (list) |item| {
        if (item.len <= path.len) continue;
        if (!std.mem.startsWith(u8, item, path)) continue;
        if (item[path.len] == '.') return true;
    }
    return false;
}
