const std = @import("std");
const core = @import("../core/mod.zig");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const StaticFilesOptions = struct {
    index_file: ?[]const u8 = "index.html",
    cache_control: ?[]const u8 = "public, max-age=60",
    allow_hidden: bool = false,
    include_in_schema: bool = false,
};

pub const StaticFilesIntegration = struct {
    directory: []const u8,
    options: StaticFilesOptions = .{},

    pub fn init(directory: []const u8) StaticFilesIntegration {
        return .{
            .directory = directory,
            .options = .{},
        };
    }

    pub fn withOptions(self: StaticFilesIntegration, options: StaticFilesOptions) StaticFilesIntegration {
        var next = self;
        next.options = options;
        return next;
    }

    pub fn mount(self: StaticFilesIntegration, app: *core.App, prefix: []const u8) !void {
        try mountStaticFiles(app, prefix, self.directory, self.options);
    }

    pub fn serve(self: StaticFilesIntegration, req: *Request, allocator: std.mem.Allocator) !Response {
        return serveStandalone(req, allocator, self.directory, self.options);
    }
};

const Mount = struct {
    prefix: []u8,
    directory: []u8,
    index_file: ?[]u8,
    cache_control: ?[]u8,
    allow_hidden: bool,
};

var mounts: std.ArrayListUnmanaged(Mount) = .empty;
var mounts_lock: std.Thread.Mutex = .{};

pub fn mountStaticFiles(
    app: *core.App,
    prefix: []const u8,
    directory: []const u8,
    options: StaticFilesOptions,
) !void {
    const normalized_prefix = try normalizePrefix(app.allocator, prefix);
    defer app.allocator.free(normalized_prefix);

    try registerMount(normalized_prefix, directory, options);

    if (std.mem.eql(u8, normalized_prefix, "/")) {
        if (options.include_in_schema) {
            try app.get("/{file_path:path}", staticFilesHandler, .{
                .summary = "Static file mount",
            });
        } else {
            try app.get("/{file_path:path}", staticFilesHandler, .{
                .summary = "Static file mount",
                .include_in_schema = false,
            });
        }
        if (options.index_file != null) {
            if (options.include_in_schema) {
                try app.get("/", staticFilesHandler, .{
                    .summary = "Static file index",
                });
            } else {
                try app.get("/", staticFilesHandler, .{
                    .summary = "Static file index",
                    .include_in_schema = false,
                });
            }
        }
        return;
    }

    const wildcard_route = try std.fmt.allocPrint(app.allocator, "{s}/{{file_path:path}}", .{normalized_prefix});
    defer app.allocator.free(wildcard_route);
    if (options.include_in_schema) {
        try app.get(wildcard_route, staticFilesHandler, .{
            .summary = "Static file mount",
        });
    } else {
        try app.get(wildcard_route, staticFilesHandler, .{
            .summary = "Static file mount",
            .include_in_schema = false,
        });
    }

    if (options.index_file != null) {
        if (options.include_in_schema) {
            try app.get(normalized_prefix, staticFilesHandler, .{
                .summary = "Static file index",
            });
        } else {
            try app.get(normalized_prefix, staticFilesHandler, .{
                .summary = "Static file index",
                .include_in_schema = false,
            });
        }
    }
}

pub fn clearMountsForTesting() void {
    const allocator = std.heap.page_allocator;
    mounts_lock.lock();
    defer mounts_lock.unlock();

    for (mounts.items) |entry| {
        allocator.free(entry.prefix);
        allocator.free(entry.directory);
        if (entry.index_file) |index_file| allocator.free(index_file);
        if (entry.cache_control) |cache_control| allocator.free(cache_control);
    }
    mounts.deinit(allocator);
    mounts = .empty;
}

fn staticFilesHandler(req: *Request, allocator: std.mem.Allocator) !Response {
    const mount_cfg = findBestMount(req.path) orelse return Response.text("not found").withStatus(.not_found);
    return serveMounted(req, allocator, mount_cfg, .{
        .index_file = mount_cfg.index_file,
        .cache_control = mount_cfg.cache_control,
        .allow_hidden = mount_cfg.allow_hidden,
        .include_in_schema = false,
    });
}

fn serveMounted(
    req: *Request,
    allocator: std.mem.Allocator,
    mount_cfg: Mount,
    options: StaticFilesOptions,
) !Response {
    const rel_path = resolveRelativePathForMount(req.path, mount_cfg.prefix, options.index_file) orelse {
        return Response.text("not found").withStatus(.not_found);
    };

    return serveFromRelativePath(req, allocator, mount_cfg.directory, rel_path, options);
}

fn serveStandalone(
    req: *Request,
    allocator: std.mem.Allocator,
    directory: []const u8,
    options: StaticFilesOptions,
) !Response {
    const rel_path = resolveRelativePathFromRoot(req.path, options.index_file) orelse {
        return Response.text("not found").withStatus(.not_found);
    };

    return serveFromRelativePath(req, allocator, directory, rel_path, options);
}

fn serveFromRelativePath(
    req: *Request,
    allocator: std.mem.Allocator,
    directory: []const u8,
    rel_path: []const u8,
    options: StaticFilesOptions,
) !Response {
    if (!isSafeRelativePath(rel_path, options.allow_hidden)) {
        return Response.text("not found").withStatus(.not_found);
    }

    const full_path = try std.fs.path.join(allocator, &.{ directory, rel_path });
    defer allocator.free(full_path);

    const stat = std.fs.cwd().statFile(full_path) catch {
        return Response.text("not found").withStatus(.not_found);
    };

    if (stat.kind != .file) {
        return Response.text("not found").withStatus(.not_found);
    }

    var response = try Response.fileFromPath(allocator, full_path);
    errdefer response.deinit(allocator);

    const etag = try buildEtag(allocator, stat);
    defer allocator.free(etag);

    if (req.header("if-none-match")) |if_none_match| {
        if (std.mem.eql(u8, std.mem.trim(u8, if_none_match, " \t"), etag)) {
            response.deinit(allocator);
            var not_modified = Response.text("").withStatus(.not_modified);
            try not_modified.setEtag(allocator, etag);
            if (options.cache_control) |cache_control| {
                try not_modified.setHeader(allocator, "cache-control", cache_control);
            }
            return not_modified;
        }
    }

    try response.setEtag(allocator, etag);
    if (options.cache_control) |cache_control| {
        try response.setHeader(allocator, "cache-control", cache_control);
    }
    return response;
}

fn registerMount(prefix: []const u8, directory: []const u8, options: StaticFilesOptions) !void {
    const allocator = std.heap.page_allocator;

    mounts_lock.lock();
    defer mounts_lock.unlock();

    for (mounts.items) |entry| {
        if (std.mem.eql(u8, entry.prefix, prefix)) return;
    }

    const owned_prefix = try allocator.dupe(u8, prefix);
    errdefer allocator.free(owned_prefix);
    const owned_directory = try allocator.dupe(u8, directory);
    errdefer allocator.free(owned_directory);

    const owned_index_file = if (options.index_file) |index_file|
        try allocator.dupe(u8, index_file)
    else
        null;
    errdefer if (owned_index_file) |index_file| allocator.free(index_file);

    const owned_cache_control = if (options.cache_control) |cache_control|
        try allocator.dupe(u8, cache_control)
    else
        null;
    errdefer if (owned_cache_control) |cache_control| allocator.free(cache_control);

    try mounts.append(allocator, .{
        .prefix = owned_prefix,
        .directory = owned_directory,
        .index_file = owned_index_file,
        .cache_control = owned_cache_control,
        .allow_hidden = options.allow_hidden,
    });
}

fn findBestMount(path: []const u8) ?Mount {
    mounts_lock.lock();
    defer mounts_lock.unlock();

    var best: ?Mount = null;
    for (mounts.items) |entry| {
        if (!prefixMatchesPath(entry.prefix, path)) continue;
        if (best == null or entry.prefix.len > best.?.prefix.len) {
            best = entry;
        }
    }
    return best;
}

fn resolveRelativePathForMount(path: []const u8, prefix: []const u8, index_file: ?[]const u8) ?[]const u8 {
    if (std.mem.eql(u8, path, prefix)) {
        return index_file;
    }

    if (std.mem.eql(u8, prefix, "/")) {
        const trimmed = std.mem.trimLeft(u8, path, "/");
        if (trimmed.len == 0) return index_file;
        return trimmed;
    }

    if (!prefixMatchesPath(prefix, path)) return null;
    if (path.len == prefix.len) return index_file;

    if (path.len == prefix.len + 1 and path[path.len - 1] == '/') {
        return index_file;
    }

    const rel = path[prefix.len + 1 ..];
    if (rel.len == 0) return index_file;
    return rel;
}

fn resolveRelativePathFromRoot(path: []const u8, index_file: ?[]const u8) ?[]const u8 {
    if (path.len == 0) return null;
    if (std.mem.eql(u8, path, "/")) return index_file;

    const trimmed = std.mem.trimLeft(u8, path, "/");
    if (trimmed.len == 0) return index_file;
    return trimmed;
}

fn normalizePrefix(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    if (prefix.len == 0 or prefix[0] != '/') return error.InvalidPrefix;

    var end = prefix.len;
    while (end > 1 and prefix[end - 1] == '/') : (end -= 1) {}
    return allocator.dupe(u8, prefix[0..end]);
}

fn prefixMatchesPath(prefix: []const u8, path: []const u8) bool {
    if (std.mem.eql(u8, prefix, "/")) return std.mem.startsWith(u8, path, "/");
    if (!std.mem.startsWith(u8, path, prefix)) return false;
    if (path.len == prefix.len) return true;
    return path[prefix.len] == '/';
}

fn isSafeRelativePath(rel_path: []const u8, allow_hidden: bool) bool {
    if (rel_path.len == 0) return false;
    if (std.fs.path.isAbsolute(rel_path)) return false;
    if (std.mem.indexOfScalar(u8, rel_path, '\\')) |_| return false;

    var seg_it = std.mem.splitScalar(u8, rel_path, '/');
    while (seg_it.next()) |segment| {
        if (segment.len == 0) continue;
        if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return false;
        if (!allow_hidden and segment[0] == '.') return false;
    }

    return true;
}

fn buildEtag(allocator: std.mem.Allocator, stat: std.fs.File.Stat) ![]u8 {
    const mtime_u64: u64 = if (stat.mtime <= 0) 0 else @as(u64, @intCast(stat.mtime));
    return std.fmt.allocPrint(allocator, "\"{x}-{x}\"", .{ stat.size, mtime_u64 });
}

test "static files mount serves files and index" {
    clearMountsForTesting();
    defer clearMountsForTesting();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("css");
    try tmp.dir.writeFile(.{ .sub_path = "index.html", .data = "<h1>home</h1>" });
    try tmp.dir.writeFile(.{ .sub_path = "css/app.css", .data = "body { color: red; }" });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var app = try core.App.init(std.testing.allocator, .{
        .title = "static",
        .version = "0.0.1",
    });
    defer app.deinit();

    const static_files = StaticFilesIntegration.init(root);
    try static_files.mount(&app, "/assets");

    var css = try app.dispatchSynthetic(.GET, "/assets/css/app.css", "");
    defer css.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, css.status);
    try std.testing.expectEqualStrings("body { color: red; }", css.body);
    try std.testing.expectEqualStrings("text/css; charset=utf-8", css.content_type);

    var index = try app.dispatchSynthetic(.GET, "/assets", "");
    defer index.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, index.status);
    try std.testing.expectEqualStrings("<h1>home</h1>", index.body);
}
