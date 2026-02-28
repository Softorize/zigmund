const std = @import("std");

/// AST nodes for the Jinja2-compatible template engine.
pub const Node = union(enum) {
    text: []const u8,
    output: Expr,
    if_stmt: IfStmt,
    for_stmt: ForStmt,
    block: Block,
    extends: []const u8,
    include: []const u8,
    set_stmt: SetStmt,
    macro: Macro,
    call_block: CallBlock,
    comment: []const u8,
    template: []const Node,
};

pub const Expr = union(enum) {
    variable: []const u8,
    string_lit: []const u8,
    integer_lit: i64,
    float_lit: f64,
    bool_lit: bool,
    none_lit,
    list_lit: []const Expr,
    unary: Unary,
    binary: Binary,
    compare: Compare,
    getattr: GetAttr,
    getitem: GetItem,
    filter: Filter,
    func_call: FuncCall,
    conditional: Conditional,
    tilde_concat: TildeConcat,
};

pub const Unary = struct {
    op: UnaryOp,
    operand: *const Expr,
};

pub const UnaryOp = enum { not, negate };

pub const Binary = struct {
    op: BinaryOp,
    left: *const Expr,
    right: *const Expr,
};

pub const BinaryOp = enum { add, sub, mul, div, mod, @"and", @"or" };

pub const Compare = struct {
    op: CompareOp,
    left: *const Expr,
    right: *const Expr,
};

pub const CompareOp = enum { eq, ne, lt, gt, le, ge, in_op, not_in };

pub const GetAttr = struct {
    object: *const Expr,
    attr: []const u8,
};

pub const GetItem = struct {
    object: *const Expr,
    index: *const Expr,
};

pub const Filter = struct {
    expr: *const Expr,
    name: []const u8,
    args: []const Expr,
};

pub const FuncCall = struct {
    name: []const u8,
    args: []const Expr,
};

pub const Conditional = struct {
    condition: *const Expr,
    true_expr: *const Expr,
    false_expr: *const Expr,
};

pub const TildeConcat = struct {
    left: *const Expr,
    right: *const Expr,
};

pub const IfStmt = struct {
    branches: []const IfBranch,
    else_body: []const Node,
};

pub const IfBranch = struct {
    condition: Expr,
    body: []const Node,
};

pub const ForStmt = struct {
    var_name: []const u8,
    iterable: Expr,
    body: []const Node,
    else_body: []const Node,
    recursive: bool,
};

pub const Block = struct {
    name: []const u8,
    body: []const Node,
};

pub const SetStmt = struct {
    name: []const u8,
    value: Expr,
};

pub const Macro = struct {
    name: []const u8,
    params: []const MacroParam,
    body: []const Node,
};

pub const MacroParam = struct {
    name: []const u8,
    default: ?Expr,
};

pub const CallBlock = struct {
    func: Expr,
    body: []const Node,
};
