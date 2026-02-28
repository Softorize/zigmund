const std = @import("std");
const Response = @import("../http/response.zig").Response;
const template = @import("../template/mod.zig");

pub const TemplateValue = union(enum) {
    string: []const u8,
    integer: i64,
    unsigned: u64,
    float: f64,
    boolean: bool,
};

pub const TemplateBinding = struct {
    key: []const u8,
    value: TemplateValue,
};

pub const TemplatesIntegration = struct {
    allocator: std.mem.Allocator,
    templates_dir: []u8,

    pub fn init(allocator: std.mem.Allocator, templates_dir: []const u8) !TemplatesIntegration {
        const owned_dir = try allocator.dupe(u8, templates_dir);
        return .{
            .allocator = allocator,
            .templates_dir = owned_dir,
        };
    }

    pub fn deinit(self: *TemplatesIntegration) void {
        self.allocator.free(self.templates_dir);
        self.templates_dir = &.{};
    }

    pub fn render(
        self: *const TemplatesIntegration,
        template_name: []const u8,
        bindings: []const TemplateBinding,
    ) ![]u8 {
        if (!isSafeTemplatePath(template_name)) return error.InvalidTemplatePath;

        const template_path = try std.fs.path.join(self.allocator, &.{ self.templates_dir, template_name });
        defer self.allocator.free(template_path);

        const template_bytes = try std.fs.cwd().readFileAlloc(self.allocator, template_path, 16 * 1024 * 1024);
        var rendered = template_bytes;
        var owns_rendered = true;
        errdefer if (owns_rendered) self.allocator.free(rendered);

        for (bindings) |binding| {
            const replacement = try templateValueToOwnedString(self.allocator, binding.value);
            defer self.allocator.free(replacement);

            const token_no_space = try std.fmt.allocPrint(self.allocator, "{{{{{s}}}}}", .{binding.key});
            defer self.allocator.free(token_no_space);
            const token_with_space = try std.fmt.allocPrint(self.allocator, "{{{{ {s} }}}}", .{binding.key});
            defer self.allocator.free(token_with_space);

            const pass_one = try replaceAll(self.allocator, rendered, token_no_space, replacement);
            if (owns_rendered) self.allocator.free(rendered);

            rendered = pass_one;
            owns_rendered = true;

            const pass_two = try replaceAll(self.allocator, rendered, token_with_space, replacement);
            self.allocator.free(rendered);

            rendered = pass_two;
            owns_rendered = true;
        }

        return rendered;
    }

    pub fn renderHtmlResponse(
        self: *const TemplatesIntegration,
        template_name: []const u8,
        bindings: []const TemplateBinding,
    ) !Response {
        const rendered = try self.render(template_name, bindings);
        return .{
            .status = .ok,
            .body = rendered,
            .content_type = "text/html; charset=utf-8",
            .owned_body = rendered,
        };
    }

    /// Render a template using the Jinja2-compatible engine.
    /// This provides full Jinja2 features: control flow, filters, inheritance, macros.
    pub fn renderJinja(
        self: *const TemplatesIntegration,
        template_name: []const u8,
        vars: []const struct { []const u8, template.Value },
    ) ![]u8 {
        var engine = template.Engine.init(self.allocator, self.templates_dir);
        defer engine.deinit();
        return try engine.render(template_name, vars);
    }

    /// Render a Jinja2 template and return it as an HTML response.
    pub fn renderJinjaHtmlResponse(
        self: *const TemplatesIntegration,
        template_name: []const u8,
        vars: []const struct { []const u8, template.Value },
    ) !Response {
        const rendered = try self.renderJinja(template_name, vars);
        return .{
            .status = .ok,
            .body = rendered,
            .content_type = "text/html; charset=utf-8",
            .owned_body = rendered,
        };
    }
};

fn isSafeTemplatePath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.fs.path.isAbsolute(path)) return false;
    if (std.mem.indexOf(u8, path, "..")) |_| return false;
    if (std.mem.indexOfScalar(u8, path, '\\')) |_| return false;
    return true;
}

fn templateValueToOwnedString(allocator: std.mem.Allocator, value: TemplateValue) ![]u8 {
    return switch (value) {
        .string => |v| allocator.dupe(u8, v),
        .integer => |v| std.fmt.allocPrint(allocator, "{d}", .{v}),
        .unsigned => |v| std.fmt.allocPrint(allocator, "{d}", .{v}),
        .float => |v| std.fmt.allocPrint(allocator, "{d}", .{v}),
        .boolean => |v| allocator.dupe(u8, if (v) "true" else "false"),
    };
}

fn replaceAll(
    allocator: std.mem.Allocator,
    input: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, input);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, cursor, needle)) |pos| {
        try out.appendSlice(allocator, input[cursor..pos]);
        try out.appendSlice(allocator, replacement);
        cursor = pos + needle.len;
    }
    try out.appendSlice(allocator, input[cursor..]);
    return out.toOwnedSlice(allocator);
}

test "template rendering replaces placeholders" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "hello.html",
        .data = "Hello {{ name }} (#{{id}})!",
    });

    const templates_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(templates_dir);

    var templates = try TemplatesIntegration.init(std.testing.allocator, templates_dir);
    defer templates.deinit();

    const bindings = [_]TemplateBinding{
        .{ .key = "name", .value = .{ .string = "Toto" } },
        .{ .key = "id", .value = .{ .unsigned = 42 } },
    };

    const rendered = try templates.render("hello.html", &bindings);
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("Hello Toto (#42)!", rendered);
}
