const std = @import("std");

pub const TokenType = enum {
    text,
    variable_start, // {{
    variable_end, // }}
    block_start, // {%
    block_end, // %}
    comment, // {# ... #}
    identifier,
    string_literal,
    integer_literal,
    float_literal,
    dot,
    comma,
    pipe, // |
    lparen,
    rparen,
    lbracket,
    rbracket,
    assign, // =
    eq, // ==
    ne, // !=
    lt,
    gt,
    le, // <=
    ge, // >=
    plus,
    minus,
    star,
    slash,
    percent, // %
    tilde, // ~
    colon,
    kw_if,
    kw_elif,
    kw_else,
    kw_endif,
    kw_for,
    kw_endfor,
    kw_in,
    kw_block,
    kw_endblock,
    kw_extends,
    kw_include,
    kw_macro,
    kw_endmacro,
    kw_call,
    kw_endcall,
    kw_set,
    kw_endset,
    kw_raw,
    kw_endraw,
    kw_not,
    kw_and,
    kw_or,
    kw_is,
    kw_true,
    kw_false,
    kw_none,
    kw_recursive,
    eof,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    line: usize,
    col: usize,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    col: usize,
    tokens: std.ArrayList(Token),
    allocator: std.mem.Allocator,
    in_tag: bool,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .col = 1,
            .tokens = .empty,
            .allocator = allocator,
            .in_tag = false,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn tokenize(self: *Lexer) ![]const Token {
        while (self.pos < self.source.len) {
            if (self.in_tag) {
                try self.readTagContent();
            } else {
                try self.readText();
            }
        }
        try self.tokens.append(self.allocator, .{ .type = .eof, .value = "", .line = self.line, .col = self.col });
        return self.tokens.items;
    }

    fn readText(self: *Lexer) !void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;

        while (self.pos < self.source.len) {
            if (self.pos + 1 < self.source.len) {
                const c0 = self.source[self.pos];
                const c1 = self.source[self.pos + 1];
                if (c0 == '{' and (c1 == '{' or c1 == '%' or c1 == '#')) break;
            }
            self.advance();
        }

        // Emit text before the tag
        if (self.pos > start) {
            try self.tokens.append(self.allocator, .{ .type = .text, .value = self.source[start..self.pos], .line = start_line, .col = start_col });
        }

        if (self.pos >= self.source.len) return;

        const c1 = self.source[self.pos + 1];

        if (c1 == '#') {
            // Comment: {# ... #}
            try self.readComment();
        } else if (c1 == '%') {
            // Check for raw block
            if (self.checkRawBlock()) return;
            try self.emitBlockStart();
        } else {
            // Variable {{ }}
            try self.emitVarStart();
        }
    }

    fn emitVarStart(self: *Lexer) !void {
        // Check for whitespace trim {%-
        const trim = self.pos + 2 < self.source.len and self.source[self.pos + 2] == '-';
        if (trim) {
            self.trimLastTextToken();
        }

        try self.tokens.append(self.allocator, .{ .type = .variable_start, .value = "{{", .line = self.line, .col = self.col });
        self.pos += 2;
        self.col += 2;
        if (trim) {
            self.pos += 1;
            self.col += 1;
        }
        self.in_tag = true;
    }

    fn emitBlockStart(self: *Lexer) !void {
        const trim = self.pos + 2 < self.source.len and self.source[self.pos + 2] == '-';
        if (trim) {
            self.trimLastTextToken();
        }

        try self.tokens.append(self.allocator, .{ .type = .block_start, .value = "{%", .line = self.line, .col = self.col });
        self.pos += 2;
        self.col += 2;
        if (trim) {
            self.pos += 1;
            self.col += 1;
        }
        self.in_tag = true;
    }

    fn readComment(self: *Lexer) !void {
        const start_line = self.line;
        const start_col = self.col;
        self.pos += 2; // skip {#
        self.col += 2;
        const content_start = self.pos;

        while (self.pos + 1 < self.source.len) {
            if (self.source[self.pos] == '#' and self.source[self.pos + 1] == '}') {
                const content = self.source[content_start..self.pos];
                try self.tokens.append(self.allocator, .{ .type = .comment, .value = content, .line = start_line, .col = start_col });
                self.pos += 2;
                self.col += 2;
                return;
            }
            self.advance();
        }
        // Unterminated comment — include whatever we have
        try self.tokens.append(self.allocator, .{ .type = .comment, .value = self.source[content_start..self.pos], .line = start_line, .col = start_col });
    }

    fn checkRawBlock(self: *Lexer) bool {
        // Check if this {%...%} contains "raw"
        const saved_pos = self.pos;
        const saved_line = self.line;
        const saved_col = self.col;

        // Skip {%
        var p = self.pos + 2;
        // Skip optional -
        if (p < self.source.len and self.source[p] == '-') p += 1;
        // Skip whitespace
        while (p < self.source.len and (self.source[p] == ' ' or self.source[p] == '\t')) p += 1;

        // Check if it starts with "raw"
        if (p + 3 <= self.source.len and std.mem.eql(u8, self.source[p .. p + 3], "raw")) {
            const after_raw = p + 3;
            // Check it's actually the keyword (not "raw_something")
            if (after_raw >= self.source.len or !isIdentChar(self.source[after_raw])) {
                // Find the matching endraw
                self.readRawBlock(saved_pos) catch return false;
                return true;
            }
        }

        // Not a raw block, restore position
        self.pos = saved_pos;
        self.line = saved_line;
        self.col = saved_col;
        return false;
    }

    fn readRawBlock(self: *Lexer, start: usize) !void {
        // Skip the {% raw %} tag
        self.pos = start + 2; // skip {%
        self.col += 2;
        while (self.pos < self.source.len and self.source[self.pos] != '%') self.advance();
        if (self.pos + 1 < self.source.len) {
            self.pos += 2; // skip %}
            self.col += 2;
        }

        const raw_start = self.pos;
        const raw_start_line = self.line;
        const raw_start_col = self.col;

        // Find {% endraw %}
        while (self.pos + 1 < self.source.len) {
            if (self.source[self.pos] == '{' and self.source[self.pos + 1] == '%') {
                var p = self.pos + 2;
                if (p < self.source.len and self.source[p] == '-') p += 1;
                while (p < self.source.len and (self.source[p] == ' ' or self.source[p] == '\t')) p += 1;
                if (p + 6 <= self.source.len and std.mem.eql(u8, self.source[p .. p + 6], "endraw")) {
                    // Found endraw
                    const raw_content = self.source[raw_start..self.pos];
                    if (raw_content.len > 0) {
                        try self.tokens.append(self.allocator, .{ .type = .text, .value = raw_content, .line = raw_start_line, .col = raw_start_col });
                    }
                    // Skip {% endraw %}
                    while (self.pos < self.source.len and !(self.source[self.pos] == '%' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '}')) self.advance();
                    if (self.pos + 1 < self.source.len) {
                        self.pos += 2;
                        self.col += 2;
                    }
                    return;
                }
            }
            self.advance();
        }
        // Unterminated raw
        if (self.pos > raw_start) {
            try self.tokens.append(self.allocator, .{ .type = .text, .value = self.source[raw_start..self.pos], .line = raw_start_line, .col = raw_start_col });
        }
    }

    fn readTagContent(self: *Lexer) !void {
        self.skipWhitespace();

        if (self.pos >= self.source.len) {
            self.in_tag = false;
            return;
        }

        const c = self.source[self.pos];

        // Check for tag end: %} or }}
        if (c == '%' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '}') {
            try self.tokens.append(self.allocator, .{ .type = .block_end, .value = "%}", .line = self.line, .col = self.col });
            self.pos += 2;
            self.col += 2;
            self.in_tag = false;
            return;
        }
        if (c == '}' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '}') {
            try self.tokens.append(self.allocator, .{ .type = .variable_end, .value = "}}", .line = self.line, .col = self.col });
            self.pos += 2;
            self.col += 2;
            self.in_tag = false;
            return;
        }
        // Check for trim end -%} or -}}
        if (c == '-') {
            if (self.pos + 2 < self.source.len) {
                if (self.source[self.pos + 1] == '%' and self.source[self.pos + 2] == '}') {
                    try self.tokens.append(self.allocator, .{ .type = .block_end, .value = "-%}", .line = self.line, .col = self.col });
                    self.pos += 3;
                    self.col += 3;
                    self.in_tag = false;
                    self.trimNextTextWhitespace();
                    return;
                }
                if (self.source[self.pos + 1] == '}' and self.source[self.pos + 2] == '}') {
                    try self.tokens.append(self.allocator, .{ .type = .variable_end, .value = "-}}", .line = self.line, .col = self.col });
                    self.pos += 3;
                    self.col += 3;
                    self.in_tag = false;
                    self.trimNextTextWhitespace();
                    return;
                }
            }
        }

        if (c == '"' or c == '\'') {
            try self.readString();
        } else if (std.ascii.isDigit(c)) {
            try self.readNumber();
        } else if (isIdentStart(c)) {
            try self.readIdentifierOrKeyword();
        } else {
            try self.readOperator();
        }
    }

    fn readString(self: *Lexer) !void {
        const quote = self.source[self.pos];
        const start = self.pos;
        self.pos += 1;
        self.col += 1;

        while (self.pos < self.source.len) {
            if (self.source[self.pos] == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 2;
                self.col += 2;
                continue;
            }
            if (self.source[self.pos] == quote) {
                self.pos += 1;
                self.col += 1;
                // Store without quotes
                try self.tokens.append(self.allocator, .{
                    .type = .string_literal,
                    .value = self.source[start + 1 .. self.pos - 1],
                    .line = self.line,
                    .col = self.col,
                });
                return;
            }
            self.advance();
        }
        // Unterminated string
        try self.tokens.append(self.allocator, .{
            .type = .string_literal,
            .value = self.source[start + 1 .. self.pos],
            .line = self.line,
            .col = self.col,
        });
    }

    fn readNumber(self: *Lexer) !void {
        const start = self.pos;
        var is_float = false;

        while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
            self.pos += 1;
            self.col += 1;
        }
        if (self.pos < self.source.len and self.source[self.pos] == '.') {
            if (self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])) {
                is_float = true;
                self.pos += 1;
                self.col += 1;
                while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                    self.pos += 1;
                    self.col += 1;
                }
            }
        }

        try self.tokens.append(self.allocator, .{
            .type = if (is_float) .float_literal else .integer_literal,
            .value = self.source[start..self.pos],
            .line = self.line,
            .col = self.col,
        });
    }

    fn readIdentifierOrKeyword(self: *Lexer) !void {
        const start = self.pos;
        while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
            self.pos += 1;
            self.col += 1;
        }

        const word = self.source[start..self.pos];
        const tt = keywordType(word) orelse .identifier;
        try self.tokens.append(self.allocator, .{ .type = tt, .value = word, .line = self.line, .col = self.col });
    }

    fn readOperator(self: *Lexer) !void {
        const c = self.source[self.pos];
        const next: u8 = if (self.pos + 1 < self.source.len) self.source[self.pos + 1] else 0;

        const result: struct { tt: TokenType, len: usize } = switch (c) {
            '.' => .{ .tt = .dot, .len = 1 },
            ',' => .{ .tt = .comma, .len = 1 },
            '|' => .{ .tt = .pipe, .len = 1 },
            '(' => .{ .tt = .lparen, .len = 1 },
            ')' => .{ .tt = .rparen, .len = 1 },
            '[' => .{ .tt = .lbracket, .len = 1 },
            ']' => .{ .tt = .rbracket, .len = 1 },
            '+' => .{ .tt = .plus, .len = 1 },
            '-' => .{ .tt = .minus, .len = 1 },
            '*' => .{ .tt = .star, .len = 1 },
            '/' => .{ .tt = .slash, .len = 1 },
            '%' => .{ .tt = .percent, .len = 1 },
            '~' => .{ .tt = .tilde, .len = 1 },
            ':' => .{ .tt = .colon, .len = 1 },
            '=' => if (next == '=') .{ .tt = .eq, .len = 2 } else .{ .tt = .assign, .len = 1 },
            '!' => if (next == '=') .{ .tt = .ne, .len = 2 } else .{ .tt = .kw_not, .len = 1 },
            '<' => if (next == '=') .{ .tt = .le, .len = 2 } else .{ .tt = .lt, .len = 1 },
            '>' => if (next == '=') .{ .tt = .ge, .len = 2 } else .{ .tt = .gt, .len = 1 },
            else => {
                // Skip unknown character
                self.pos += 1;
                self.col += 1;
                return;
            },
        };

        try self.tokens.append(self.allocator, .{
            .type = result.tt,
            .value = self.source[self.pos .. self.pos + result.len],
            .line = self.line,
            .col = self.col,
        });
        self.pos += result.len;
        self.col += result.len;
    }

    fn advance(self: *Lexer) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
            self.pos += 1;
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t' or self.source[self.pos] == '\n' or self.source[self.pos] == '\r')) {
            self.advance();
        }
    }

    fn trimLastTextToken(self: *Lexer) void {
        if (self.tokens.items.len > 0) {
            const last = &self.tokens.items[self.tokens.items.len - 1];
            if (last.type == .text) {
                last.value = std.mem.trimRight(u8, last.value, " \t\n\r");
            }
        }
    }

    fn trimNextTextWhitespace(self: *Lexer) void {
        // The next text token will have leading whitespace trimmed.
        // We handle this by skipping whitespace in the source right now.
        while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t' or self.source[self.pos] == '\n' or self.source[self.pos] == '\r')) {
            self.advance();
        }
    }
};

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn keywordType(word: []const u8) ?TokenType {
    const map = std.StaticStringMap(TokenType).initComptime(.{
        .{ "if", .kw_if },
        .{ "elif", .kw_elif },
        .{ "else", .kw_else },
        .{ "endif", .kw_endif },
        .{ "for", .kw_for },
        .{ "endfor", .kw_endfor },
        .{ "in", .kw_in },
        .{ "block", .kw_block },
        .{ "endblock", .kw_endblock },
        .{ "extends", .kw_extends },
        .{ "include", .kw_include },
        .{ "macro", .kw_macro },
        .{ "endmacro", .kw_endmacro },
        .{ "call", .kw_call },
        .{ "endcall", .kw_endcall },
        .{ "set", .kw_set },
        .{ "endset", .kw_endset },
        .{ "raw", .kw_raw },
        .{ "endraw", .kw_endraw },
        .{ "not", .kw_not },
        .{ "and", .kw_and },
        .{ "or", .kw_or },
        .{ "is", .kw_is },
        .{ "true", .kw_true },
        .{ "True", .kw_true },
        .{ "false", .kw_false },
        .{ "False", .kw_false },
        .{ "none", .kw_none },
        .{ "None", .kw_none },
        .{ "recursive", .kw_recursive },
    });
    return map.get(word);
}

// ─── Tests ─────────────────────────────────────────────────────────────

test "lexer tokenizes variable expression" {
    var lex = Lexer.init(std.testing.allocator, "Hello {{ name }}!");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    try std.testing.expectEqual(TokenType.text, tokens[0].type);
    try std.testing.expectEqualStrings("Hello ", tokens[0].value);
    try std.testing.expectEqual(TokenType.variable_start, tokens[1].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[2].type);
    try std.testing.expectEqualStrings("name", tokens[2].value);
    try std.testing.expectEqual(TokenType.variable_end, tokens[3].type);
    try std.testing.expectEqual(TokenType.text, tokens[4].type);
    try std.testing.expectEqualStrings("!", tokens[4].value);
}

test "lexer tokenizes block tag" {
    var lex = Lexer.init(std.testing.allocator, "{% if x == 1 %}yes{% endif %}");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    try std.testing.expectEqual(TokenType.block_start, tokens[0].type);
    try std.testing.expectEqual(TokenType.kw_if, tokens[1].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[2].type);
    try std.testing.expectEqualStrings("x", tokens[2].value);
    try std.testing.expectEqual(TokenType.eq, tokens[3].type);
    try std.testing.expectEqual(TokenType.integer_literal, tokens[4].type);
    try std.testing.expectEqual(TokenType.block_end, tokens[5].type);
}

test "lexer handles comments" {
    var lex = Lexer.init(std.testing.allocator, "before{# this is a comment #}after");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    try std.testing.expectEqual(TokenType.text, tokens[0].type);
    try std.testing.expectEqualStrings("before", tokens[0].value);
    try std.testing.expectEqual(TokenType.comment, tokens[1].type);
    try std.testing.expectEqual(TokenType.text, tokens[2].type);
    try std.testing.expectEqualStrings("after", tokens[2].value);
}

test "lexer handles raw blocks" {
    var lex = Lexer.init(std.testing.allocator, "{% raw %}{{ not_a_var }}{% endraw %}");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    try std.testing.expectEqual(TokenType.text, tokens[0].type);
    try std.testing.expectEqualStrings("{{ not_a_var }}", tokens[0].value);
}

test "lexer handles string literals" {
    var lex = Lexer.init(std.testing.allocator, "{{ \"hello world\" }}");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    try std.testing.expectEqual(TokenType.variable_start, tokens[0].type);
    try std.testing.expectEqual(TokenType.string_literal, tokens[1].type);
    try std.testing.expectEqualStrings("hello world", tokens[1].value);
}

test "lexer handles filter pipe" {
    var lex = Lexer.init(std.testing.allocator, "{{ name|upper }}");
    defer lex.deinit();
    const tokens = try lex.tokenize();

    try std.testing.expectEqual(TokenType.variable_start, tokens[0].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[1].type);
    try std.testing.expectEqual(TokenType.pipe, tokens[2].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[3].type);
    try std.testing.expectEqualStrings("upper", tokens[3].value);
}
