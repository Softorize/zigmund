const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/status/";

/// Demonstrates HTTP status codes via std.http.Status and Response.withStatus.
fn statusDemo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .type = "zigmund.status is std.http.Status",
        .common_codes = .{
            .ok = @intFromEnum(zigmund.status.ok),
            .created = @intFromEnum(zigmund.status.created),
            .no_content = @intFromEnum(zigmund.status.no_content),
            .bad_request = @intFromEnum(zigmund.status.bad_request),
            .unauthorized = @intFromEnum(zigmund.status.unauthorized),
            .forbidden = @intFromEnum(zigmund.status.forbidden),
            .not_found = @intFromEnum(zigmund.status.not_found),
            .unprocessable_content = @intFromEnum(zigmund.status.unprocessable_content),
            .internal_server_error = @intFromEnum(zigmund.status.internal_server_error),
        },
        .usage = .{
            .route_option = "RouteOptions.status_code = .created",
            .response_method = "response.withStatus(.created)",
            .direct_field = "response.status = .created",
        },
    });
}

fn createdExample(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return (try zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "Resource created",
    })).withStatus(.created);
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/status", statusDemo, .{
        .summary = "HTTP status codes reference (std.http.Status)",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_status_codes",
    });
    try app.post("/reference/status/create", createdExample, .{
        .summary = "Response with 201 Created status",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_status_created",
        .status_code = .created,
    });
}
