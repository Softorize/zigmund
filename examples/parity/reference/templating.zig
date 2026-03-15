const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/templating/";

/// Demonstrates TemplatesIntegration API reference.
fn templatingInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .api = .{
            .init = "TemplatesIntegration.init(allocator, templates_dir)",
            .render = "templates.render(template_name, bindings) -> []u8",
            .render_html = "templates.renderHtmlResponse(template_name, bindings) -> Response",
            .render_jinja = "templates.renderJinja(template_name, vars) -> []u8",
            .render_jinja_html = "templates.renderJinjaHtmlResponse(template_name, vars) -> Response",
        },
        .binding_types = .{
            .TemplateBinding = "{ .key = name, .value = TemplateValue }",
            .TemplateValue = "string | integer | unsigned | float | boolean",
        },
        .template_syntax = .{
            .simple = "{{ variable_name }} - replaced with binding value",
            .jinja = "Full Jinja2: {% if %}, {% for %}, {{ var|filter }}, {% extends %}",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/templating", templatingInfo, .{
        .summary = "TemplatesIntegration: render, renderHtmlResponse, Jinja2",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_templating_overview",
    });
}
