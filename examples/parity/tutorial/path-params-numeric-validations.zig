const std = @import("std");
const zigmund = @import("zigmund");

fn readVersion(
    version: zigmund.Path(i64, .{
        .alias = "version",
        .ge = 1,
        .le = 10,
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .version = version.value.?,
        .valid = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/path-params-numeric-validations/{version}", readVersion, .{
        .summary = "Validate numeric path params with constraints",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_validate_numeric_path_params",
    });
}
