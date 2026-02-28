const std = @import("std");
const lexer_mod = @import("lexer.zig");
const parser_mod = @import("parser.zig");
const ast = @import("ast.zig");

/// File-based template loader with compiled template cache and path traversal protection.
pub const FileLoader = struct {
    templates_dir: []const u8,
    cache: std.StringHashMap([]const ast.Node),
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, templates_dir: []const u8) FileLoader {
        return .{
            .templates_dir = templates_dir,
            .cache = std.StringHashMap([]const ast.Node).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *FileLoader) void {
        self.cache.deinit();
        self.arena.deinit();
    }

    pub fn load(self: *FileLoader, name: []const u8) ![]const ast.Node {
        // Check cache
        if (self.cache.get(name)) |cached| return cached;

        // Validate path safety
        if (!isSafePath(name)) return error.InvalidTemplatePath;

        // Build full path
        const alloc = self.arena.allocator();
        const full_path = try std.fs.path.join(alloc, &.{ self.templates_dir, name });

        // Read file
        const source = std.fs.cwd().readFileAlloc(alloc, full_path, 16 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return error.TemplateNotFound,
            else => return err,
        };

        // Lex
        var lex = lexer_mod.Lexer.init(alloc, source);
        const tokens = try lex.tokenize();

        // Parse
        var parser = parser_mod.Parser.init(alloc, tokens);
        const nodes = try parser.parse();

        // Cache
        try self.cache.put(try alloc.dupe(u8, name), nodes);

        return nodes;
    }

    /// Create a loader callback suitable for the renderer.
    pub fn loaderFn(self: *FileLoader) *const fn ([]const u8, std.mem.Allocator) anyerror![]const ast.Node {
        // Store reference in a static-like wrapper
        // Since we can't capture, we use a different approach:
        // The renderer's loader will be set directly in the Engine
        _ = self;
        return &dummyLoader;
    }
};

fn dummyLoader(_: []const u8, _: std.mem.Allocator) anyerror![]const ast.Node {
    return error.TemplateNotFound;
}

fn isSafePath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.fs.path.isAbsolute(path)) return false;
    if (std.mem.indexOf(u8, path, "..")) |_| return false;
    if (std.mem.indexOfScalar(u8, path, '\\')) |_| return false;
    // No null bytes
    if (std.mem.indexOfScalar(u8, path, 0)) |_| return false;
    return true;
}

test "path safety validation" {
    try std.testing.expect(isSafePath("template.html"));
    try std.testing.expect(isSafePath("dir/template.html"));
    try std.testing.expect(!isSafePath(""));
    try std.testing.expect(!isSafePath("/etc/passwd"));
    try std.testing.expect(!isSafePath("../secret.html"));
    try std.testing.expect(!isSafePath("dir\\file.html"));
}
