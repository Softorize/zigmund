pub const Value = @import("value.zig").Value;
pub const Context = @import("value.zig").Context;
pub const Lexer = @import("lexer.zig").Lexer;
pub const TokenType = @import("lexer.zig").TokenType;
pub const Parser = @import("parser.zig").Parser;
pub const Node = @import("ast.zig").Node;
pub const Expr = @import("ast.zig").Expr;
pub const FilterRegistry = @import("filters.zig").FilterRegistry;
pub const FilterFn = @import("filters.zig").FilterFn;
pub const htmlEscape = @import("filters.zig").htmlEscape;
pub const Renderer = @import("renderer.zig").Renderer;
pub const RenderOptions = @import("renderer.zig").RenderOptions;
pub const FileLoader = @import("loader.zig").FileLoader;

const std = @import("std");

/// High-level convenience: parse and render a template string in one call.
pub fn renderString(
    allocator: std.mem.Allocator,
    source: []const u8,
    vars: []const struct { []const u8, Value },
) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Lex
    var lex = Lexer.init(a, source);
    const tokens = try lex.tokenize();

    // Parse
    var parser = Parser.init(a, tokens);
    const nodes = try parser.parse();

    // Build context
    var ctx = Context.init(a);
    defer ctx.deinit();
    for (vars) |entry| try ctx.set(entry[0], entry[1]);

    // Render
    var filters = FilterRegistry.init(a);
    defer filters.deinit();
    var renderer = Renderer.init(a, &ctx, &filters, .{});
    defer renderer.deinit();

    const result = try renderer.render(nodes);
    return allocator.dupe(u8, result);
}

/// Full-featured template engine with file loading, caching, and inheritance.
pub const Engine = struct {
    loader: FileLoader,
    filters: FilterRegistry,
    auto_escape: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, templates_dir: []const u8) Engine {
        return .{
            .loader = FileLoader.init(allocator, templates_dir),
            .filters = FilterRegistry.init(allocator),
            .auto_escape = true,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Engine) void {
        self.loader.deinit();
        self.filters.deinit();
    }

    pub fn render(
        self: *Engine,
        template_name: []const u8,
        vars: []const struct { []const u8, Value },
    ) ![]u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const nodes = try self.loader.load(template_name);

        var ctx = Context.init(a);
        defer ctx.deinit();
        for (vars) |entry| try ctx.set(entry[0], entry[1]);

        var renderer = Renderer.init(a, &ctx, &self.filters, .{ .auto_escape = self.auto_escape });
        defer renderer.deinit();

        // Wire up loader for includes/extends
        const LoaderBridge = struct {
            var engine_ref: *Engine = undefined;
            fn loadTemplate(name: []const u8, _: std.mem.Allocator) anyerror![]const Node {
                return engine_ref.loader.load(name);
            }
        };
        LoaderBridge.engine_ref = self;
        renderer.loader = &LoaderBridge.loadTemplate;

        const result = try renderer.render(nodes);
        return self.allocator.dupe(u8, result);
    }

    pub fn renderToResponse(
        self: *Engine,
        template_name: []const u8,
        vars: []const struct { []const u8, Value },
    ) !struct { body: []u8, content_type: []const u8 } {
        const body = try self.render(template_name, vars);
        return .{
            .body = body,
            .content_type = "text/html; charset=utf-8",
        };
    }

    pub fn addFilter(self: *Engine, name: []const u8, func: FilterFn) !void {
        try self.filters.register(name, func);
    }
};

// ─── Tests ─────────────────────────────────────────────────────────────

test "renderString convenience function" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "Hello {{ name }}!", &.{
        .{ "name", Value{ .string = "World" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Hello World!", result);
}

test "renderString with filter" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ name|upper }}", &.{
        .{ "name", Value{ .string = "world" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("WORLD", result);
}

test "renderString with if/else" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% if show %}yes{% else %}no{% endif %}", &.{
        .{ "show", Value{ .boolean = true } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("yes", result);
}

test "renderString with for loop" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .string = "a" }, .{ .string = "b" }, .{ .string = "c" } };
    const result = try renderString(alloc, "{% for x in items %}{{ x }}{% endfor %}", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("abc", result);
}

test "renderString with loop.index" {
    const alloc = std.testing.allocator;
    const items = [_]Value{ .{ .string = "a" }, .{ .string = "b" } };
    const result = try renderString(alloc, "{% for x in items %}{{ loop.index }}{% endfor %}", &.{
        .{ "items", Value{ .list = &items } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("12", result);
}

test "renderString auto-escapes HTML" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ html }}", &.{
        .{ "html", Value{ .string = "<script>" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("&lt;script&gt;", result);
}

test "renderString safe filter bypasses escaping" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{{ html|safe }}", &.{
        .{ "html", Value{ .string = "<b>bold</b>" } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("<b>bold</b>", result);
}

test "renderString with set" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% set x = 42 %}{{ x }}", &.{});
    defer alloc.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "renderString with comparison" {
    const alloc = std.testing.allocator;
    const result = try renderString(alloc, "{% if x > 5 %}big{% else %}small{% endif %}", &.{
        .{ "x", Value{ .integer = 10 } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("big", result);
}

test "renderString with dot access" {
    const alloc = std.testing.allocator;
    const keys = [_][]const u8{"name"};
    const vals = [_]Value{.{ .string = "Alice" }};
    const result = try renderString(alloc, "{{ user.name }}", &.{
        .{ "user", Value{ .map = .{ .keys = &keys, .values = &vals } } },
    });
    defer alloc.free(result);
    try std.testing.expectEqualStrings("Alice", result);
}

// Reference all submodule tests
comptime {
    _ = @import("value.zig");
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("filters.zig");
    _ = @import("renderer.zig");
    _ = @import("loader.zig");
}
