const std = @import("std");

fn isIdentChar(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_';
}

fn parsePublicExportNames(allocator: std.mem.Allocator, source: []const u8) ![][]u8 {
    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "pub const ") and !std.mem.startsWith(u8, line, "pub fn ")) continue;

        const name_start: usize = if (std.mem.startsWith(u8, line, "pub const "))
            "pub const ".len
        else
            "pub fn ".len;

        var idx = name_start;
        while (idx < line.len and isIdentChar(line[idx])) : (idx += 1) {}
        if (idx == name_start) continue;

        try names.append(allocator, try allocator.dupe(u8, line[name_start..idx]));
    }

    std.mem.sort([]u8, names.items, {}, struct {
        fn lessThan(_: void, lhs: []u8, rhs: []u8) bool {
            return std.mem.order(u8, lhs, rhs) == .lt;
        }
    }.lessThan);

    return names.toOwnedSlice(allocator);
}

fn parseSnapshotNames(allocator: std.mem.Allocator, snapshot: []const u8) ![][]u8 {
    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, snapshot, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        try names.append(allocator, try allocator.dupe(u8, trimmed));
    }

    std.mem.sort([]u8, names.items, {}, struct {
        fn lessThan(_: void, lhs: []u8, rhs: []u8) bool {
            return std.mem.order(u8, lhs, rhs) == .lt;
        }
    }.lessThan);

    return names.toOwnedSlice(allocator);
}

fn freeNames(allocator: std.mem.Allocator, names: [][]u8) void {
    for (names) |name| allocator.free(name);
    allocator.free(names);
}

test "public api surface matches snapshot" {
    const allocator = std.testing.allocator;
    const source = try std.fs.cwd().readFileAlloc(
        allocator,
        "src/zigmund.zig",
        2 * 1024 * 1024,
    );
    defer allocator.free(source);

    const snapshot = try std.fs.cwd().readFileAlloc(
        allocator,
        "tools/release/api-surface-v0.txt",
        2 * 1024 * 1024,
    );
    defer allocator.free(snapshot);

    const parsed_source = try parsePublicExportNames(allocator, source);
    defer freeNames(allocator, parsed_source);

    const parsed_snapshot = try parseSnapshotNames(allocator, snapshot);
    defer freeNames(allocator, parsed_snapshot);

    try std.testing.expectEqual(parsed_snapshot.len, parsed_source.len);
    for (parsed_snapshot, parsed_source) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }
}
