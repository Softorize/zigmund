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

test "parity tooling and example scaffolds exist" {
    try std.testing.expect(fileExists("tools/parity/fetch_fastapi_sitemap.sh"));
    try std.testing.expect(fileExists("tools/parity/check_parity_gate.sh"));
    try std.testing.expect(fileExists("examples/parity/tutorial/first-steps.zig"));
}

test "parity baseline examples are implemented (no stub markers)" {
    const implemented_examples = [_][]const u8{
        "examples/parity/tutorial/first-steps.zig",
        "examples/parity/tutorial/background-tasks.zig",
        "examples/parity/tutorial/index.zig",
        "examples/parity/tutorial/metadata.zig",
        "examples/parity/tutorial/path-params.zig",
        "examples/parity/tutorial/query-params.zig",
        "examples/parity/tutorial/body.zig",
        "examples/parity/tutorial/response-status-code.zig",
        "examples/parity/tutorial/handling-errors.zig",
        "examples/parity/tutorial/security__first-steps.zig",
        "examples/parity/tutorial/path-params-numeric-validations.zig",
        "examples/parity/tutorial/query-params-str-validations.zig",
        "examples/parity/tutorial/path-operation-configuration.zig",
        "examples/parity/tutorial/response-model.zig",
        "examples/parity/tutorial/request-forms.zig",
        "examples/parity/tutorial/request-files.zig",
        "examples/parity/tutorial/static-files.zig",
        "examples/parity/tutorial/sql-databases.zig",
        "examples/parity/how-to/graphql.zig",
        "examples/parity/advanced/templates.zig",
        "examples/parity/advanced/settings.zig",
    };

    for (implemented_examples) |example_path| {
        try std.testing.expect(fileExists(example_path));
        try std.testing.expect(!fileContains(example_path, "ZIGMUND_PARITY_STUB"));
    }
}
