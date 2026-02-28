const std = @import("std");
const ast = @import("ast.zig");
const Node = ast.Node;
const Expr = ast.Expr;
const Value = @import("value.zig").Value;
const Context = @import("value.zig").Context;
const FilterRegistry = @import("filters.zig").FilterRegistry;
const htmlEscape = @import("filters.zig").htmlEscape;

pub const RenderError = error{
    UndefinedVariable,
    UndefinedFilter,
    TypeError,
    OutOfMemory,
    InvalidOperation,
};

pub const RenderOptions = struct {
    auto_escape: bool = true,
};

pub const Renderer = struct {
    ctx: *Context,
    filters: *FilterRegistry,
    arena: std.mem.Allocator,
    options: RenderOptions,
    /// Block overrides from child templates (extends/inheritance).
    block_overrides: std.StringHashMap([]const Node),
    /// Macros defined in the template.
    macros: std.StringHashMap(ast.Macro),
    /// Template loader callback for includes/extends.
    loader: ?*const fn ([]const u8, std.mem.Allocator) anyerror![]const Node,

    pub fn init(arena: std.mem.Allocator, ctx: *Context, filters: *FilterRegistry, options: RenderOptions) Renderer {
        return .{
            .ctx = ctx,
            .filters = filters,
            .arena = arena,
            .options = options,
            .block_overrides = std.StringHashMap([]const Node).init(arena),
            .macros = std.StringHashMap(ast.Macro).init(arena),
            .loader = null,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.block_overrides.deinit();
        self.macros.deinit();
    }

    pub fn render(self: *Renderer, nodes: []const Node) (RenderError || anyerror)![]u8 {
        var buf: std.ArrayList(u8) = .empty;

        // First pass: collect extends and block overrides
        var extends_name: ?[]const u8 = null;
        for (nodes) |node| {
            switch (node) {
                .extends => |name| {
                    extends_name = name;
                },
                .block => |block| {
                    try self.block_overrides.put(block.name, block.body);
                },
                .macro => |macro| {
                    try self.macros.put(macro.name, macro);
                },
                else => {},
            }
        }

        if (extends_name) |parent_name| {
            // Load and render parent template
            if (self.loader) |load| {
                const parent_nodes = try load(parent_name, self.arena);
                return try self.render(parent_nodes);
            }
            return RenderError.InvalidOperation;
        }

        // Normal rendering
        for (nodes) |node| {
            try self.renderNode(&buf, node);
        }
        return buf.toOwnedSlice(self.arena);
    }

    fn renderNode(self: *Renderer, buf: *std.ArrayList(u8), node: Node) anyerror!void {
        switch (node) {
            .text => |t| try buf.appendSlice(self.arena, t),
            .comment => {},
            .output => |expr| {
                const val = try self.evalExpr(expr);
                const s = try val.toString(self.arena);
                defer self.arena.free(s);
                if (self.options.auto_escape and val != .safe_string) {
                    const escaped = try htmlEscape(self.arena, s);
                    defer self.arena.free(escaped);
                    try buf.appendSlice(self.arena, escaped);
                } else {
                    try buf.appendSlice(self.arena, s);
                }
            },
            .if_stmt => |stmt| {
                var matched = false;
                for (stmt.branches) |branch| {
                    const cond = try self.evalExpr(branch.condition);
                    if (cond.isTruthy()) {
                        try self.ctx.pushScope();
                        for (branch.body) |child| try self.renderNode(buf, child);
                        self.ctx.popScope();
                        matched = true;
                        break;
                    }
                }
                if (!matched and stmt.else_body.len > 0) {
                    try self.ctx.pushScope();
                    for (stmt.else_body) |child| try self.renderNode(buf, child);
                    self.ctx.popScope();
                }
            },
            .for_stmt => |stmt| try self.renderFor(buf, stmt),
            .block => |block| {
                // Check for overrides (from extends)
                const body = self.block_overrides.get(block.name) orelse block.body;
                try self.ctx.pushScope();
                for (body) |child| try self.renderNode(buf, child);
                self.ctx.popScope();
            },
            .set_stmt => |stmt| {
                const val = try self.evalExpr(stmt.value);
                try self.ctx.set(stmt.name, val);
            },
            .include => |name| {
                if (self.loader) |load| {
                    const inc_nodes = try load(name, self.arena);
                    for (inc_nodes) |child| try self.renderNode(buf, child);
                }
            },
            .macro => |macro| {
                try self.macros.put(macro.name, macro);
            },
            .call_block => |cb| {
                // Render the body and pass as caller()
                var body_buf: std.ArrayList(u8) = .empty;
                for (cb.body) |child| try self.renderNode(&body_buf, child);
                const body_str = try body_buf.toOwnedSlice(self.arena);
                try self.ctx.pushScope();
                try self.ctx.set("caller", Value{ .safe_string = body_str });
                const val = try self.evalExpr(cb.func);
                const s = try val.toString(self.arena);
                defer self.arena.free(s);
                try buf.appendSlice(self.arena, s);
                self.ctx.popScope();
            },
            .extends => {}, // handled in first pass
            .template => |children| {
                for (children) |child| try self.renderNode(buf, child);
            },
        }
    }

    fn renderFor(self: *Renderer, buf: *std.ArrayList(u8), stmt: ast.ForStmt) anyerror!void {
        const iterable = try self.evalExpr(stmt.iterable);
        const items = switch (iterable) {
            .list => |l| l,
            .string => |s| blk: {
                // Iterate over characters
                const chars = try self.arena.alloc(Value, s.len);
                for (s, 0..) |c, i| {
                    const ch = try self.arena.alloc(u8, 1);
                    ch[0] = c;
                    chars[i] = Value{ .string = ch };
                }
                break :blk @as([]const Value, chars);
            },
            .map => |m| blk: {
                // Iterate over keys
                const keys = try self.arena.alloc(Value, m.keys.len);
                for (m.keys, 0..) |k, i| keys[i] = Value{ .string = k };
                break :blk @as([]const Value, keys);
            },
            else => {
                // Empty iterable — render else body
                if (stmt.else_body.len > 0) {
                    for (stmt.else_body) |child| try self.renderNode(buf, child);
                }
                return;
            },
        };

        if (items.len == 0) {
            if (stmt.else_body.len > 0) {
                for (stmt.else_body) |child| try self.renderNode(buf, child);
            }
            return;
        }

        for (items, 0..) |item, i| {
            try self.ctx.pushScope();

            // Set loop variable
            try self.ctx.set(stmt.var_name, item);

            // Set loop context
            const loop_keys = try self.arena.alloc([]const u8, 7);
            const loop_vals = try self.arena.alloc(Value, 7);
            loop_keys[0] = "index";
            loop_vals[0] = Value{ .integer = @intCast(i + 1) };
            loop_keys[1] = "index0";
            loop_vals[1] = Value{ .integer = @intCast(i) };
            loop_keys[2] = "first";
            loop_vals[2] = Value{ .boolean = i == 0 };
            loop_keys[3] = "last";
            loop_vals[3] = Value{ .boolean = i == items.len - 1 };
            loop_keys[4] = "length";
            loop_vals[4] = Value{ .integer = @intCast(items.len) };
            loop_keys[5] = "revindex";
            loop_vals[5] = Value{ .integer = @intCast(items.len - i) };
            loop_keys[6] = "revindex0";
            loop_vals[6] = Value{ .integer = @intCast(items.len - i - 1) };

            try self.ctx.set("loop", Value{ .map = .{ .keys = loop_keys, .values = loop_vals } });

            for (stmt.body) |child| try self.renderNode(buf, child);

            self.ctx.popScope();
        }
    }

    // ─── Expression evaluation ─────────────────────────────────────────

    pub fn evalExpr(self: *Renderer, expr: Expr) anyerror!Value {
        return switch (expr) {
            .variable => |name| self.ctx.get(name) orelse Value.none,
            .string_lit => |s| Value{ .string = s },
            .integer_lit => |i| Value{ .integer = i },
            .float_lit => |f| Value{ .float = f },
            .bool_lit => |b| Value{ .boolean = b },
            .none_lit => Value.none,
            .list_lit => |items| {
                const vals = try self.arena.alloc(Value, items.len);
                for (items, 0..) |item, i| vals[i] = try self.evalExpr(item);
                return Value{ .list = vals };
            },
            .unary => |u| self.evalUnary(u),
            .binary => |b| self.evalBinary(b),
            .compare => |c| self.evalCompare(c),
            .getattr => |g| {
                const obj = try self.evalExpr(g.object.*);
                return obj.getAttr(g.attr) orelse Value.none;
            },
            .getitem => |g| {
                const obj = try self.evalExpr(g.object.*);
                const idx = try self.evalExpr(g.index.*);
                return obj.getItem(idx) orelse Value.none;
            },
            .filter => |f| self.evalFilter(f),
            .func_call => |fc| self.evalFuncCall(fc),
            .conditional => |c| {
                const cond = try self.evalExpr(c.condition.*);
                if (cond.isTruthy()) return self.evalExpr(c.true_expr.*);
                return self.evalExpr(c.false_expr.*);
            },
            .tilde_concat => |t| {
                const left = try self.evalExpr(t.left.*);
                const right = try self.evalExpr(t.right.*);
                const ls = try left.toString(self.arena);
                defer self.arena.free(ls);
                const rs = try right.toString(self.arena);
                defer self.arena.free(rs);
                const result = try std.fmt.allocPrint(self.arena, "{s}{s}", .{ ls, rs });
                return Value{ .safe_string = result };
            },
        };
    }

    fn evalUnary(self: *Renderer, u: ast.Unary) !Value {
        const operand = try self.evalExpr(u.operand.*);
        return switch (u.op) {
            .not => Value{ .boolean = !operand.isTruthy() },
            .negate => switch (operand) {
                .integer => |i| Value{ .integer = -i },
                .float => |f| Value{ .float = -f },
                else => Value{ .integer = 0 },
            },
        };
    }

    fn evalBinary(self: *Renderer, b: ast.Binary) !Value {
        const left = try self.evalExpr(b.left.*);
        const right = try self.evalExpr(b.right.*);

        return switch (b.op) {
            .add => blk: {
                if (left == .string or right == .string) {
                    // String concatenation
                    const ls = try left.toString(self.arena);
                    defer self.arena.free(ls);
                    const rs = try right.toString(self.arena);
                    defer self.arena.free(rs);
                    break :blk Value{ .safe_string = try std.fmt.allocPrint(self.arena, "{s}{s}", .{ ls, rs }) };
                }
                if (left == .float or right == .float) {
                    break :blk Value{ .float = left.toFloat() + right.toFloat() };
                }
                break :blk Value{ .integer = (left.toInteger() orelse 0) + (right.toInteger() orelse 0) };
            },
            .sub => blk: {
                if (left == .float or right == .float) {
                    break :blk Value{ .float = left.toFloat() - right.toFloat() };
                }
                break :blk Value{ .integer = (left.toInteger() orelse 0) - (right.toInteger() orelse 0) };
            },
            .mul => blk: {
                if (left == .float or right == .float) {
                    break :blk Value{ .float = left.toFloat() * right.toFloat() };
                }
                break :blk Value{ .integer = (left.toInteger() orelse 0) * (right.toInteger() orelse 0) };
            },
            .div => blk: {
                const r = right.toFloat();
                if (r == 0.0) break :blk Value{ .float = 0.0 };
                break :blk Value{ .float = left.toFloat() / r };
            },
            .mod => blk: {
                const r = right.toInteger() orelse 0;
                if (r == 0) break :blk Value{ .integer = 0 };
                break :blk Value{ .integer = @mod(left.toInteger() orelse 0, r) };
            },
            .@"and" => Value{ .boolean = left.isTruthy() and right.isTruthy() },
            .@"or" => if (left.isTruthy()) left else right,
        };
    }

    fn evalCompare(self: *Renderer, c: ast.Compare) !Value {
        const left = try self.evalExpr(c.left.*);
        const right = try self.evalExpr(c.right.*);

        const result: bool = switch (c.op) {
            .eq => left.eql(right),
            .ne => !left.eql(right),
            .lt => left.toFloat() < right.toFloat(),
            .gt => left.toFloat() > right.toFloat(),
            .le => left.toFloat() <= right.toFloat(),
            .ge => left.toFloat() >= right.toFloat(),
            .in_op => self.evalIn(left, right),
            .not_in => !self.evalIn(left, right),
        };
        return Value{ .boolean = result };
    }

    fn evalIn(self: *Renderer, needle: Value, haystack: Value) bool {
        _ = self;
        return switch (haystack) {
            .list => |l| {
                for (l) |item| {
                    if (needle.eql(item)) return true;
                }
                return false;
            },
            .string => |s| {
                const ns = switch (needle) {
                    .string => |n| n,
                    else => return false,
                };
                return std.mem.indexOf(u8, s, ns) != null;
            },
            .map => |m| {
                const key = switch (needle) {
                    .string => |n| n,
                    else => return false,
                };
                for (m.keys) |k| {
                    if (std.mem.eql(u8, k, key)) return true;
                }
                return false;
            },
            else => false,
        };
    }

    fn evalFilter(self: *Renderer, f: ast.Filter) !Value {
        const val = try self.evalExpr(f.expr.*);
        var args = try self.arena.alloc(Value, f.args.len);
        for (f.args, 0..) |arg, i| args[i] = try self.evalExpr(arg);

        const filter_fn = self.filters.get(f.name) orelse return RenderError.UndefinedFilter;
        return filter_fn(val, args, self.arena);
    }

    fn evalFuncCall(self: *Renderer, fc: ast.FuncCall) !Value {
        // Check for built-in functions
        if (std.mem.eql(u8, fc.name, "range")) {
            return self.evalRange(fc.args);
        }
        if (std.mem.eql(u8, fc.name, "super")) {
            // In block inheritance, return the parent block content
            // For now, return empty
            return Value{ .safe_string = "" };
        }
        if (std.mem.eql(u8, fc.name, "caller")) {
            return self.ctx.get("caller") orelse Value{ .safe_string = "" };
        }
        if (std.mem.eql(u8, fc.name, "lipsum")) {
            return Value{ .safe_string = "Lorem ipsum dolor sit amet, consectetur adipiscing elit." };
        }
        if (std.mem.eql(u8, fc.name, "dict")) {
            // Simple dict() constructor — not fully featured
            return Value.none;
        }

        // Check for macros
        if (self.macros.get(fc.name)) |macro| {
            return self.evalMacroCall(macro, fc.args);
        }

        return Value.none;
    }

    fn evalMacroCall(self: *Renderer, macro: ast.Macro, call_args: []const ast.Expr) !Value {
        try self.ctx.pushScope();
        defer self.ctx.popScope();

        // Bind arguments
        for (macro.params, 0..) |param, i| {
            const val = if (i < call_args.len)
                try self.evalExpr(call_args[i])
            else if (param.default) |d|
                try self.evalExpr(d)
            else
                Value.none;
            try self.ctx.set(param.name, val);
        }

        // Render body
        var buf: std.ArrayList(u8) = .empty;
        for (macro.body) |child| try self.renderNode(&buf, child);
        return Value{ .safe_string = try buf.toOwnedSlice(self.arena) };
    }

    fn evalRange(self: *Renderer, args: []const ast.Expr) !Value {
        if (args.len == 0) return Value{ .list = &.{} };

        const first = try self.evalExpr(args[0]);
        var start: i64 = 0;
        var end: i64 = first.toInteger() orelse 0;

        if (args.len >= 2) {
            start = end;
            const second = try self.evalExpr(args[1]);
            end = second.toInteger() orelse 0;
        }

        if (end <= start) return Value{ .list = &.{} };

        const count: usize = @intCast(end - start);
        const items = try self.arena.alloc(Value, count);
        for (0..count) |i| {
            items[i] = Value{ .integer = start + @as(i64, @intCast(i)) };
        }
        return Value{ .list = items };
    }
};

// ─── Tests ─────────────────────────────────────────────────────────────

test "renderer renders simple variable" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var ctx = Context.init(a);
    defer ctx.deinit();
    try ctx.set("name", Value{ .string = "World" });

    var filters = FilterRegistry.init(a);
    defer filters.deinit();

    var renderer = Renderer.init(a, &ctx, &filters, .{});
    defer renderer.deinit();

    const nodes = &[_]Node{
        .{ .text = "Hello " },
        .{ .output = .{ .variable = "name" } },
        .{ .text = "!" },
    };
    const result = try renderer.render(nodes);
    try std.testing.expectEqualStrings("Hello World!", result);
}

test "renderer renders if/else" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var ctx = Context.init(a);
    defer ctx.deinit();
    try ctx.set("show", Value{ .boolean = false });

    var filters = FilterRegistry.init(a);
    defer filters.deinit();

    var renderer = Renderer.init(a, &ctx, &filters, .{});
    defer renderer.deinit();

    const branches = &[_]ast.IfBranch{
        .{ .condition = .{ .variable = "show" }, .body = &.{.{ .text = "yes" }} },
    };
    const nodes = &[_]Node{
        .{ .if_stmt = .{ .branches = branches, .else_body = &.{.{ .text = "no" }} } },
    };
    const result = try renderer.render(nodes);
    try std.testing.expectEqualStrings("no", result);
}

test "renderer renders for loop with loop vars" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var ctx = Context.init(a);
    defer ctx.deinit();
    const items = &[_]Value{ .{ .string = "a" }, .{ .string = "b" } };
    try ctx.set("items", Value{ .list = items });

    var filters = FilterRegistry.init(a);
    defer filters.deinit();

    var renderer = Renderer.init(a, &ctx, &filters, .{});
    defer renderer.deinit();

    const body = &[_]Node{.{ .output = .{ .variable = "item" } }};
    const nodes = &[_]Node{
        .{ .for_stmt = .{
            .var_name = "item",
            .iterable = .{ .variable = "items" },
            .body = body,
            .else_body = &.{},
            .recursive = false,
        } },
    };
    const result = try renderer.render(nodes);
    try std.testing.expectEqualStrings("ab", result);
}

test "renderer auto-escapes HTML" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var ctx = Context.init(a);
    defer ctx.deinit();
    try ctx.set("html", Value{ .string = "<b>bold</b>" });

    var filters = FilterRegistry.init(a);
    defer filters.deinit();

    var renderer = Renderer.init(a, &ctx, &filters, .{});
    defer renderer.deinit();

    const nodes = &[_]Node{.{ .output = .{ .variable = "html" } }};
    const result = try renderer.render(nodes);
    try std.testing.expectEqualStrings("&lt;b&gt;bold&lt;/b&gt;", result);
}
