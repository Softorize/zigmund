const std = @import("std");

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

test "parity tooling and example scaffolds exist" {
    try std.testing.expect(fileExists("tools/parity/fetch_fastapi_sitemap.sh"));
    try std.testing.expect(fileExists("tools/parity/check_parity_gate.sh"));
    try std.testing.expect(fileExists("examples/parity/tutorial/first-steps.zig"));
}
