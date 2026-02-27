const std = @import("std");

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn fileContains(path: []const u8, needle: []const u8) bool {
    const data = std.fs.cwd().readFileAlloc(std.testing.allocator, path, 1024 * 1024) catch return false;
    defer std.testing.allocator.free(data);
    return std.mem.indexOf(u8, data, needle) != null;
}

fn verifyNoStubMarkersInDir(dir: std.fs.Dir, rel_prefix: []const u8, checked_count: *usize) !void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const rel_path = try std.fs.path.join(std.testing.allocator, &.{ rel_prefix, entry.name });
        defer std.testing.allocator.free(rel_path);

        switch (entry.kind) {
            .directory => {
                var child = try dir.openDir(entry.name, .{ .iterate = true });
                defer child.close();
                try verifyNoStubMarkersInDir(child, rel_path, checked_count);
            },
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
                try std.testing.expect(!fileContains(rel_path, "ZIGMUND_PARITY_STUB"));
                checked_count.* += 1;
            },
            else => {},
        }
    }
}

test "parity tooling and example scaffolds exist" {
    try std.testing.expect(fileExists("tools/parity/fetch_fastapi_sitemap.sh"));
    try std.testing.expect(fileExists("tools/parity/check_parity_gate.sh"));
    try std.testing.expect(fileExists("examples/parity/tutorial/first-steps.zig"));
}

test "all parity examples are non-stub implementations" {
    var dir = try std.fs.cwd().openDir("examples/parity", .{ .iterate = true });
    defer dir.close();

    var checked_count: usize = 0;
    try verifyNoStubMarkersInDir(dir, "examples/parity", &checked_count);
    try std.testing.expect(checked_count >= 116);
}
