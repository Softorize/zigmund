const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/strict-content-type/";

const StrictPayload = struct {
    name: []const u8,
    value: u32,
};

fn strictEndpoint(
    body: zigmund.Body(StrictPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .received_name = body.value.?.name,
        .received_value = body.value.?.value,
        .strict_validation = true,
    });
}

fn nonStrictEndpoint(
    body: zigmund.Body(StrictPayload, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .parity = "implemented",
        .page = source_page,
        .received_name = body.value.?.name,
        .received_value = body.value.?.value,
        .strict_validation = false,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/advanced/strict-content-type/strict", strictEndpoint, .{
        .summary = "Accept request only with strict content-type validation",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_strict_content_type_strict",
        .strict_validation = true,
    });
    try app.post("/advanced/strict-content-type/lenient", nonStrictEndpoint, .{
        .summary = "Accept request with lenient content-type validation",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_strict_content_type_lenient",
        .strict_validation = false,
    });
}
