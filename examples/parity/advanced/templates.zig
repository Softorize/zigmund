const std = @import("std");
const zigmund = @import("zigmund");

fn renderTemplate(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var templates = zigmund.TemplatesIntegration.init(
        allocator,
        "examples/parity/assets/templates",
    ) catch {
        return zigmund.Response.html("<h1>Template directory not configured</h1>");
    };
    defer templates.deinit();

    const bindings = [_]zigmund.TemplateBinding{
        .{ .key = "name", .value = .{ .string = "zigmund" } },
        .{ .key = "id", .value = .{ .unsigned = 42 } },
    };

    return templates.renderHtmlResponse("index.html", &bindings) catch {
        return zigmund.Response.html("<h1>Template file not found</h1>");
    };
}

fn templateInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .templates_dir = "examples/parity/assets/templates",
        .template = "index.html",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/templates", renderTemplate, .{
        .summary = "Render HTML using template integration",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_templates_render",
    });
    try app.get("/advanced/templates/info", templateInfo, .{
        .summary = "Template integration metadata",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_templates_info",
    });
}
