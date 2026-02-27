const std = @import("std");
const zigmund = @import("zigmund");

fn readConfiguredOperation(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .operation = "configured",
        .ok = true,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/tutorial/path-operation-configuration/items", readConfiguredOperation, .{
        .name = "configured_operation",
        .summary = "Configured path operation",
        .description = "Demonstrates route metadata fields used for docs and OpenAPI generation.",
        .tags = &.{ "parity", "tutorial", "configuration" },
        .operation_id = "tutorial_path_operation_configuration_items",
        .responses = &.{
            .{
                .status_code = .bad_request,
                .description = "Validation or input error",
            },
            .{
                .status_code = .internal_server_error,
                .description = "Unhandled server error",
            },
        },
    });
}
