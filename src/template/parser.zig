const std = @import("std");
const lexer_mod = @import("lexer.zig");
const ast = @import("ast.zig");
const Token = lexer_mod.Token;
const TokenType = lexer_mod.TokenType;
const Node = ast.Node;
const Expr = ast.Expr;

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidSyntax,
    OutOfMemory,
};

pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator, tokens: []const Token) Parser {
        return .{
            .tokens = tokens,
            .pos = 0,
            .arena = arena,
        };
    }

    pub fn parse(self: *Parser) ParseError![]const Node {
        return self.parseBody(&.{});
    }

    fn parseBody(self: *Parser, stop_keywords: []const TokenType) ParseError![]const Node {
        var nodes: std.ArrayList(Node) = .empty;

        while (self.pos < self.tokens.len) {
            const tok = self.current();

            if (tok.type == .eof) break;

            // Check stop conditions
            for (stop_keywords) |sk| {
                if (tok.type == sk) return nodes.toOwnedSlice(self.arena) catch return ParseError.OutOfMemory;
            }

            // Also check if next token after block_start is a stop keyword
            if (tok.type == .block_start) {
                const next = self.peek(1);
                if (next) |n| {
                    for (stop_keywords) |sk| {
                        if (n.type == sk) return nodes.toOwnedSlice(self.arena) catch return ParseError.OutOfMemory;
                    }
                }
            }

            const node = try self.parseNode();
            nodes.append(self.arena, node) catch return ParseError.OutOfMemory;
        }

        return nodes.toOwnedSlice(self.arena) catch return ParseError.OutOfMemory;
    }

    fn parseNode(self: *Parser) ParseError!Node {
        const tok = self.current();
        return switch (tok.type) {
            .text => blk: {
                self.pos += 1;
                break :blk Node{ .text = tok.value };
            },
            .comment => blk: {
                self.pos += 1;
                break :blk Node{ .comment = tok.value };
            },
            .variable_start => try self.parseOutput(),
            .block_start => try self.parseBlockTag(),
            else => blk: {
                self.pos += 1;
                break :blk Node{ .text = "" };
            },
        };
    }

    fn parseOutput(self: *Parser) ParseError!Node {
        self.pos += 1; // skip {{
        const expr = try self.parseExpr();
        try self.expect(.variable_end);
        return Node{ .output = expr };
    }

    fn parseBlockTag(self: *Parser) ParseError!Node {
        self.pos += 1; // skip {%
        const kw = self.current();

        return switch (kw.type) {
            .kw_if => try self.parseIf(),
            .kw_for => try self.parseFor(),
            .kw_block => try self.parseBlock(),
            .kw_extends => try self.parseExtends(),
            .kw_include => try self.parseInclude(),
            .kw_set => try self.parseSet(),
            .kw_macro => try self.parseMacro(),
            .kw_call => try self.parseCallBlock(),
            else => {
                // Skip unknown block
                while (self.pos < self.tokens.len and self.current().type != .block_end) self.pos += 1;
                if (self.pos < self.tokens.len) self.pos += 1;
                return Node{ .text = "" };
            },
        };
    }

    fn parseIf(self: *Parser) ParseError!Node {
        var branches: std.ArrayList(ast.IfBranch) = .empty;

        // Parse {% if condition %}
        self.pos += 1; // skip 'if'
        const cond = try self.parseExpr();
        try self.expect(.block_end);
        const body = try self.parseBody(&.{ .kw_elif, .kw_else, .kw_endif });

        branches.append(self.arena, .{ .condition = cond, .body = body }) catch return ParseError.OutOfMemory;

        // Parse {% elif ... %}
        while (self.pos < self.tokens.len) {
            if (self.current().type == .block_start) {
                if (self.peek(1)) |next| {
                    if (next.type == .kw_elif) {
                        self.pos += 2; // skip {% elif
                        const elif_cond = try self.parseExpr();
                        try self.expect(.block_end);
                        const elif_body = try self.parseBody(&.{ .kw_elif, .kw_else, .kw_endif });
                        branches.append(self.arena, .{ .condition = elif_cond, .body = elif_body }) catch return ParseError.OutOfMemory;
                        continue;
                    }
                }
            }
            break;
        }

        // Parse {% else %}
        var else_body: []const Node = &.{};
        if (self.pos < self.tokens.len and self.current().type == .block_start) {
            if (self.peek(1)) |next| {
                if (next.type == .kw_else) {
                    self.pos += 2; // skip {% else
                    try self.expect(.block_end);
                    else_body = try self.parseBody(&.{.kw_endif});
                }
            }
        }

        // Expect {% endif %}
        if (self.pos < self.tokens.len and self.current().type == .block_start) {
            self.pos += 1;
        }
        if (self.pos < self.tokens.len and self.current().type == .kw_endif) {
            self.pos += 1;
        }
        if (self.pos < self.tokens.len and self.current().type == .block_end) {
            self.pos += 1;
        }

        return Node{ .if_stmt = .{
            .branches = branches.toOwnedSlice(self.arena) catch return ParseError.OutOfMemory,
            .else_body = else_body,
        } };
    }

    fn parseFor(self: *Parser) ParseError!Node {
        self.pos += 1; // skip 'for'
        const var_name = self.current().value;
        self.pos += 1;

        try self.expect(.kw_in);

        const iterable = try self.parseExpr();

        // Check for recursive
        var recursive = false;
        if (self.pos < self.tokens.len and self.current().type == .kw_recursive) {
            recursive = true;
            self.pos += 1;
        }

        try self.expect(.block_end);

        const body = try self.parseBody(&.{ .kw_else, .kw_endfor });

        // Check for {% else %}
        var else_body: []const Node = &.{};
        if (self.pos < self.tokens.len and self.current().type == .block_start) {
            if (self.peek(1)) |next| {
                if (next.type == .kw_else) {
                    self.pos += 2;
                    try self.expect(.block_end);
                    else_body = try self.parseBody(&.{.kw_endfor});
                }
            }
        }

        // Expect {% endfor %}
        if (self.pos < self.tokens.len and self.current().type == .block_start) self.pos += 1;
        if (self.pos < self.tokens.len and self.current().type == .kw_endfor) self.pos += 1;
        if (self.pos < self.tokens.len and self.current().type == .block_end) self.pos += 1;

        return Node{ .for_stmt = .{
            .var_name = var_name,
            .iterable = iterable,
            .body = body,
            .else_body = else_body,
            .recursive = recursive,
        } };
    }

    fn parseBlock(self: *Parser) ParseError!Node {
        self.pos += 1; // skip 'block'
        const name = self.current().value;
        self.pos += 1;
        try self.expect(.block_end);

        const body = try self.parseBody(&.{.kw_endblock});

        // Expect {% endblock %}
        if (self.pos < self.tokens.len and self.current().type == .block_start) self.pos += 1;
        if (self.pos < self.tokens.len and self.current().type == .kw_endblock) self.pos += 1;
        // Optional block name after endblock
        if (self.pos < self.tokens.len and self.current().type == .identifier) self.pos += 1;
        if (self.pos < self.tokens.len and self.current().type == .block_end) self.pos += 1;

        return Node{ .block = .{ .name = name, .body = body } };
    }

    fn parseExtends(self: *Parser) ParseError!Node {
        self.pos += 1; // skip 'extends'
        const name = self.current().value;
        self.pos += 1;
        try self.expect(.block_end);
        return Node{ .extends = name };
    }

    fn parseInclude(self: *Parser) ParseError!Node {
        self.pos += 1; // skip 'include'
        const name = self.current().value;
        self.pos += 1;
        try self.expect(.block_end);
        return Node{ .include = name };
    }

    fn parseSet(self: *Parser) ParseError!Node {
        self.pos += 1; // skip 'set'
        const name = self.current().value;
        self.pos += 1;
        try self.expect(.assign);
        const value = try self.parseExpr();
        try self.expect(.block_end);
        return Node{ .set_stmt = .{ .name = name, .value = value } };
    }

    fn parseMacro(self: *Parser) ParseError!Node {
        self.pos += 1; // skip 'macro'
        const name = self.current().value;
        self.pos += 1;

        var params: std.ArrayList(ast.MacroParam) = .empty;

        if (self.current().type == .lparen) {
            self.pos += 1; // skip (
            while (self.pos < self.tokens.len and self.current().type != .rparen) {
                if (self.current().type == .comma) {
                    self.pos += 1;
                    continue;
                }
                const param_name = self.current().value;
                self.pos += 1;
                var default: ?Expr = null;
                if (self.pos < self.tokens.len and self.current().type == .assign) {
                    self.pos += 1;
                    default = try self.parseExpr();
                }
                params.append(self.arena, .{ .name = param_name, .default = default }) catch return ParseError.OutOfMemory;
            }
            if (self.pos < self.tokens.len) self.pos += 1; // skip )
        }

        try self.expect(.block_end);
        const body = try self.parseBody(&.{.kw_endmacro});

        // Expect {% endmacro %}
        if (self.pos < self.tokens.len and self.current().type == .block_start) self.pos += 1;
        if (self.pos < self.tokens.len and self.current().type == .kw_endmacro) self.pos += 1;
        if (self.pos < self.tokens.len and self.current().type == .block_end) self.pos += 1;

        return Node{ .macro = .{
            .name = name,
            .params = params.toOwnedSlice(self.arena) catch return ParseError.OutOfMemory,
            .body = body,
        } };
    }

    fn parseCallBlock(self: *Parser) ParseError!Node {
        self.pos += 1; // skip 'call'
        const func = try self.parseExpr();
        try self.expect(.block_end);
        const body = try self.parseBody(&.{.kw_endcall});

        // Expect {% endcall %}
        if (self.pos < self.tokens.len and self.current().type == .block_start) self.pos += 1;
        if (self.pos < self.tokens.len and self.current().type == .kw_endcall) self.pos += 1;
        if (self.pos < self.tokens.len and self.current().type == .block_end) self.pos += 1;

        return Node{ .call_block = .{ .func = func, .body = body } };
    }

    // ─── Expression parsing (precedence climbing) ─────────────────────

    fn parseExpr(self: *Parser) ParseError!Expr {
        return self.parseOr();
    }

    fn parseOr(self: *Parser) ParseError!Expr {
        var left = try self.parseAnd();
        while (self.pos < self.tokens.len and self.current().type == .kw_or) {
            self.pos += 1;
            const right = try self.parseAnd();
            const left_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            const right_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            left_ptr.* = left;
            right_ptr.* = right;
            left = Expr{ .binary = .{ .op = .@"or", .left = left_ptr, .right = right_ptr } };
        }
        return left;
    }

    fn parseAnd(self: *Parser) ParseError!Expr {
        var left = try self.parseNot();
        while (self.pos < self.tokens.len and self.current().type == .kw_and) {
            self.pos += 1;
            const right = try self.parseNot();
            const left_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            const right_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            left_ptr.* = left;
            right_ptr.* = right;
            left = Expr{ .binary = .{ .op = .@"and", .left = left_ptr, .right = right_ptr } };
        }
        return left;
    }

    fn parseNot(self: *Parser) ParseError!Expr {
        if (self.pos < self.tokens.len and self.current().type == .kw_not) {
            self.pos += 1;
            const operand = try self.parseNot();
            const operand_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            operand_ptr.* = operand;
            return Expr{ .unary = .{ .op = .not, .operand = operand_ptr } };
        }
        return self.parseComparison();
    }

    fn parseComparison(self: *Parser) ParseError!Expr {
        var left = try self.parseTilde();

        while (self.pos < self.tokens.len) {
            const op: ast.CompareOp = switch (self.current().type) {
                .eq => .eq,
                .ne => .ne,
                .lt => .lt,
                .gt => .gt,
                .le => .le,
                .ge => .ge,
                .kw_in => .in_op,
                .kw_not => blk: {
                    // "not in"
                    if (self.peek(1)) |next| {
                        if (next.type == .kw_in) {
                            self.pos += 1;
                            break :blk .not_in;
                        }
                    }
                    break;
                },
                else => break,
            };
            self.pos += 1;
            const right = try self.parseTilde();
            const left_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            const right_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            left_ptr.* = left;
            right_ptr.* = right;
            left = Expr{ .compare = .{ .op = op, .left = left_ptr, .right = right_ptr } };
        }

        // Check for inline if: expr if condition else other
        if (self.pos < self.tokens.len and self.current().type == .kw_if) {
            self.pos += 1;
            const condition = try self.parseOr();
            var false_expr: Expr = .none_lit;
            if (self.pos < self.tokens.len and self.current().type == .kw_else) {
                self.pos += 1;
                false_expr = try self.parseExpr();
            }
            const cond_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            const true_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            const false_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            cond_ptr.* = condition;
            true_ptr.* = left;
            false_ptr.* = false_expr;
            left = Expr{ .conditional = .{ .condition = cond_ptr, .true_expr = true_ptr, .false_expr = false_ptr } };
        }

        return left;
    }

    fn parseTilde(self: *Parser) ParseError!Expr {
        var left = try self.parseAddSub();
        while (self.pos < self.tokens.len and self.current().type == .tilde) {
            self.pos += 1;
            const right = try self.parseAddSub();
            const left_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            const right_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            left_ptr.* = left;
            right_ptr.* = right;
            left = Expr{ .tilde_concat = .{ .left = left_ptr, .right = right_ptr } };
        }
        return left;
    }

    fn parseAddSub(self: *Parser) ParseError!Expr {
        var left = try self.parseMulDiv();
        while (self.pos < self.tokens.len) {
            const op: ast.BinaryOp = switch (self.current().type) {
                .plus => .add,
                .minus => .sub,
                else => break,
            };
            self.pos += 1;
            const right = try self.parseMulDiv();
            const left_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            const right_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            left_ptr.* = left;
            right_ptr.* = right;
            left = Expr{ .binary = .{ .op = op, .left = left_ptr, .right = right_ptr } };
        }
        return left;
    }

    fn parseMulDiv(self: *Parser) ParseError!Expr {
        var left = try self.parseUnary();
        while (self.pos < self.tokens.len) {
            const op: ast.BinaryOp = switch (self.current().type) {
                .star => .mul,
                .slash => .div,
                .percent => .mod,
                else => break,
            };
            self.pos += 1;
            const right = try self.parseUnary();
            const left_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            const right_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            left_ptr.* = left;
            right_ptr.* = right;
            left = Expr{ .binary = .{ .op = op, .left = left_ptr, .right = right_ptr } };
        }
        return left;
    }

    fn parseUnary(self: *Parser) ParseError!Expr {
        if (self.pos < self.tokens.len and self.current().type == .minus) {
            self.pos += 1;
            const operand = try self.parsePostfix();
            const operand_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
            operand_ptr.* = operand;
            return Expr{ .unary = .{ .op = .negate, .operand = operand_ptr } };
        }
        return self.parsePostfix();
    }

    fn parsePostfix(self: *Parser) ParseError!Expr {
        var expr = try self.parsePrimary();

        while (self.pos < self.tokens.len) {
            const tt = self.current().type;
            if (tt == .dot) {
                self.pos += 1;
                const attr = self.current().value;
                self.pos += 1;

                // Check if it's a method call like dict.items()
                if (self.pos < self.tokens.len and self.current().type == .lparen) {
                    self.pos += 1; // skip (
                    var args: std.ArrayList(Expr) = .empty;
                    while (self.pos < self.tokens.len and self.current().type != .rparen) {
                        if (self.current().type == .comma) {
                            self.pos += 1;
                            continue;
                        }
                        const arg = try self.parseExpr();
                        args.append(self.arena, arg) catch return ParseError.OutOfMemory;
                    }
                    if (self.pos < self.tokens.len) self.pos += 1; // skip )
                    // Treat as a filter on the object
                    const expr_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
                    expr_ptr.* = expr;
                    expr = Expr{ .filter = .{
                        .expr = expr_ptr,
                        .name = attr,
                        .args = args.toOwnedSlice(self.arena) catch return ParseError.OutOfMemory,
                    } };
                } else {
                    const expr_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
                    expr_ptr.* = expr;
                    expr = Expr{ .getattr = .{ .object = expr_ptr, .attr = attr } };
                }
            } else if (tt == .lbracket) {
                self.pos += 1;
                const index = try self.parseExpr();
                try self.expect(.rbracket);
                const expr_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
                const index_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
                expr_ptr.* = expr;
                index_ptr.* = index;
                expr = Expr{ .getitem = .{ .object = expr_ptr, .index = index_ptr } };
            } else if (tt == .pipe) {
                self.pos += 1;
                const filter_name = self.current().value;
                self.pos += 1;

                var args: std.ArrayList(Expr) = .empty;
                if (self.pos < self.tokens.len and self.current().type == .lparen) {
                    self.pos += 1;
                    while (self.pos < self.tokens.len and self.current().type != .rparen) {
                        if (self.current().type == .comma) {
                            self.pos += 1;
                            continue;
                        }
                        const arg = try self.parseExpr();
                        args.append(self.arena, arg) catch return ParseError.OutOfMemory;
                    }
                    if (self.pos < self.tokens.len) self.pos += 1; // skip )
                }

                const expr_ptr = self.arena.create(Expr) catch return ParseError.OutOfMemory;
                expr_ptr.* = expr;
                expr = Expr{ .filter = .{
                    .expr = expr_ptr,
                    .name = filter_name,
                    .args = args.toOwnedSlice(self.arena) catch return ParseError.OutOfMemory,
                } };
            } else {
                break;
            }
        }

        return expr;
    }

    fn parsePrimary(self: *Parser) ParseError!Expr {
        if (self.pos >= self.tokens.len) return ParseError.UnexpectedEof;

        const tok = self.current();
        return switch (tok.type) {
            .string_literal => blk: {
                self.pos += 1;
                break :blk Expr{ .string_lit = tok.value };
            },
            .integer_literal => blk: {
                self.pos += 1;
                const val = std.fmt.parseInt(i64, tok.value, 10) catch return ParseError.InvalidSyntax;
                break :blk Expr{ .integer_lit = val };
            },
            .float_literal => blk: {
                self.pos += 1;
                const val = std.fmt.parseFloat(f64, tok.value) catch return ParseError.InvalidSyntax;
                break :blk Expr{ .float_lit = val };
            },
            .kw_true => blk: {
                self.pos += 1;
                break :blk Expr{ .bool_lit = true };
            },
            .kw_false => blk: {
                self.pos += 1;
                break :blk Expr{ .bool_lit = false };
            },
            .kw_none => blk: {
                self.pos += 1;
                break :blk .none_lit;
            },
            .identifier => blk: {
                self.pos += 1;
                // Check if it's a function call
                if (self.pos < self.tokens.len and self.current().type == .lparen) {
                    self.pos += 1;
                    var args: std.ArrayList(Expr) = .empty;
                    while (self.pos < self.tokens.len and self.current().type != .rparen) {
                        if (self.current().type == .comma) {
                            self.pos += 1;
                            continue;
                        }
                        const arg = try self.parseExpr();
                        args.append(self.arena, arg) catch return ParseError.OutOfMemory;
                    }
                    if (self.pos < self.tokens.len) self.pos += 1; // skip )
                    break :blk Expr{ .func_call = .{
                        .name = tok.value,
                        .args = args.toOwnedSlice(self.arena) catch return ParseError.OutOfMemory,
                    } };
                }
                break :blk Expr{ .variable = tok.value };
            },
            .lparen => blk: {
                self.pos += 1;
                const expr = try self.parseExpr();
                try self.expect(.rparen);
                break :blk expr;
            },
            .lbracket => blk: {
                self.pos += 1;
                var items: std.ArrayList(Expr) = .empty;
                while (self.pos < self.tokens.len and self.current().type != .rbracket) {
                    if (self.current().type == .comma) {
                        self.pos += 1;
                        continue;
                    }
                    const item = try self.parseExpr();
                    items.append(self.arena, item) catch return ParseError.OutOfMemory;
                }
                if (self.pos < self.tokens.len) self.pos += 1; // skip ]
                break :blk Expr{ .list_lit = items.toOwnedSlice(self.arena) catch return ParseError.OutOfMemory };
            },
            else => ParseError.UnexpectedToken,
        };
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    fn current(self: *const Parser) Token {
        if (self.pos >= self.tokens.len) return .{ .type = .eof, .value = "", .line = 0, .col = 0 };
        return self.tokens[self.pos];
    }

    fn peek(self: *const Parser, offset: usize) ?Token {
        const idx = self.pos + offset;
        if (idx >= self.tokens.len) return null;
        return self.tokens[idx];
    }

    fn expect(self: *Parser, expected: TokenType) ParseError!void {
        if (self.pos >= self.tokens.len) return ParseError.UnexpectedEof;
        if (self.current().type != expected) return ParseError.UnexpectedToken;
        self.pos += 1;
    }
};

// ─── Tests ─────────────────────────────────────────────────────────────

test "parser parses variable output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = @import("lexer.zig").Lexer.init(alloc, "{{ name }}");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(alloc, tokens);
    const nodes = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expect(nodes[0] == .output);
    try std.testing.expect(nodes[0].output == .variable);
    try std.testing.expectEqualStrings("name", nodes[0].output.variable);
}

test "parser parses if/else" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = @import("lexer.zig").Lexer.init(alloc, "{% if x %}yes{% else %}no{% endif %}");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(alloc, tokens);
    const nodes = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expect(nodes[0] == .if_stmt);
    try std.testing.expectEqual(@as(usize, 1), nodes[0].if_stmt.branches.len);
    try std.testing.expectEqual(@as(usize, 1), nodes[0].if_stmt.else_body.len);
}

test "parser parses for loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = @import("lexer.zig").Lexer.init(alloc, "{% for item in items %}{{ item }}{% endfor %}");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(alloc, tokens);
    const nodes = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expect(nodes[0] == .for_stmt);
    try std.testing.expectEqualStrings("item", nodes[0].for_stmt.var_name);
}

test "parser parses filter chains" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = @import("lexer.zig").Lexer.init(alloc, "{{ name|upper|trim }}");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(alloc, tokens);
    const nodes = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expect(nodes[0] == .output);
    try std.testing.expect(nodes[0].output == .filter);
    try std.testing.expectEqualStrings("trim", nodes[0].output.filter.name);
}

test "parser parses arithmetic expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lex = @import("lexer.zig").Lexer.init(alloc, "{{ 1 + 2 * 3 }}");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    var parser = Parser.init(alloc, tokens);
    const nodes = try parser.parse();
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    // Should be add(1, mul(2, 3)) due to precedence
    try std.testing.expect(nodes[0].output == .binary);
    try std.testing.expect(nodes[0].output.binary.op == .add);
}
