const std = @import("std");
const types = @import("../core/types.zig");
const Request = @import("../http/request.zig").Request;
const security = @import("../security/mod.zig");

pub const ResolverFn = *const fn (req: *Request, allocator: std.mem.Allocator) anyerror!?[]const u8;
pub const CleanupFn = Request.DependencyCleanupFn;

pub const Dependant = struct {
    name: []const u8,
    required: bool = true,
    use_cache: bool = true,
    cache_scope: types.DependencyCacheScope = .request,
    depends_on: []const []const u8 = &.{},
    scopes: []const []const u8 = &.{},
};

pub const RunError = error{
    MissingDependency,
    Unauthorized,
    InsufficientScope,
    DependencyExecutionFailed,
    DependencyCycleDetected,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .empty,
    app_cache: std.StringHashMapUnmanaged([]u8) = .empty,
    app_cache_lock: std.Thread.Mutex = .{},

    const Entry = struct {
        name: []u8,
        resolver: ResolverFn,
        cleanup: ?CleanupFn = null,
    };

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.deinit(self.allocator);

        self.app_cache_lock.lock();
        defer self.app_cache_lock.unlock();

        var cache_it = self.app_cache.iterator();
        while (cache_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.app_cache.deinit(self.allocator);
    }

    pub fn register(self: *Registry, name: []const u8, resolver: anytype) !void {
        return self.registerInternal(name, resolver, null);
    }

    pub fn registerWithCleanup(
        self: *Registry,
        name: []const u8,
        resolver: anytype,
        cleanup: anytype,
    ) !void {
        return self.registerInternal(name, resolver, normalizeCleanup(cleanup));
    }

    pub fn lookup(self: *const Registry, name: []const u8) ?ResolverFn {
        const entry = self.lookupEntry(name) orelse return null;
        return entry.resolver;
    }

    fn lookupEntry(self: *const Registry, name: []const u8) ?*const Entry {
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }

    pub fn runRouteDependencies(
        self: *Registry,
        req: *Request,
        specs: []const types.DependencySpec,
        allocator: std.mem.Allocator,
    ) RunError!void {
        var graph = DependencyGraph.init(allocator);
        defer graph.deinit();

        for (specs) |spec| {
            graph.add(.{
                .name = spec.name,
                .required = spec.required,
                .use_cache = spec.use_cache,
                .cache_scope = spec.cache_scope,
                .depends_on = spec.depends_on,
                .scopes = spec.scopes,
            }) catch return error.DependencyExecutionFailed;
        }

        const ordered = graph.solve(allocator) catch |err| switch (err) {
            error.DependencyCycleDetected => return error.DependencyCycleDetected,
            error.OutOfMemory => return error.DependencyExecutionFailed,
        };
        defer allocator.free(ordered);

        for (ordered) |idx| {
            const spec = graph.nodes.items[idx];

            if (spec.use_cache) {
                switch (spec.cache_scope) {
                    .request => {
                        if (req.dependency(spec.name) != null) continue;
                    },
                    .app => {
                        const seeded_from_app_cache = self.seedFromAppCache(req, spec.name) catch {
                            return error.DependencyExecutionFailed;
                        };
                        if (seeded_from_app_cache) continue;
                    },
                }
            }

            const has_prereqs = self.ensurePrerequisites(req, spec.depends_on) catch {
                return error.DependencyExecutionFailed;
            };
            if (!has_prereqs) {
                if (spec.required) return error.MissingDependency;
                continue;
            }

            if (spec.scopes.len > 0) {
                security.setRequiredScopes(req, spec.scopes) catch return error.DependencyExecutionFailed;
            }

            const entry = self.lookupEntry(spec.name) orelse {
                if (spec.required) return error.MissingDependency;
                continue;
            };

            const maybe_value = entry.resolver(req, allocator) catch |err| switch (err) {
                error.Unauthorized => return error.Unauthorized,
                else => return error.DependencyExecutionFailed,
            };

            if (maybe_value) |value| {
                req.setDependencyValue(spec.name, value) catch return error.DependencyExecutionFailed;
                if (entry.cleanup) |cleanup| {
                    if (spec.cache_scope == .request) {
                        req.registerDependencyCleanup(spec.name, value, cleanup) catch {
                            return error.DependencyExecutionFailed;
                        };
                    }
                }

                if (spec.use_cache and spec.cache_scope == .app) {
                    self.setAppCacheValue(spec.name, value) catch return error.DependencyExecutionFailed;
                }
            }

            if (spec.scopes.len > 0 and !security.hasRequiredScopes(req, spec.scopes)) {
                return error.InsufficientScope;
            }
        }
    }

    fn ensurePrerequisites(
        self: *Registry,
        req: *Request,
        depends_on: []const []const u8,
    ) !bool {
        for (depends_on) |name| {
            if (req.dependency(name) != null) continue;
            if (try self.seedFromAppCache(req, name)) continue;
            return false;
        }
        return true;
    }

    fn seedFromAppCache(self: *Registry, req: *Request, name: []const u8) !bool {
        self.app_cache_lock.lock();
        defer self.app_cache_lock.unlock();

        const cached = self.app_cache.get(name) orelse return false;
        try req.setDependencyValue(name, cached);
        return true;
    }

    fn setAppCacheValue(self: *Registry, key: []const u8, value: []const u8) !void {
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        self.app_cache_lock.lock();
        defer self.app_cache_lock.unlock();

        if (self.app_cache.fetchRemove(key)) |removed| {
            self.allocator.free(removed.value);
        }
        try self.app_cache.put(self.allocator, key, owned_value);
    }

    fn registerInternal(
        self: *Registry,
        name: []const u8,
        resolver: anytype,
        cleanup: ?CleanupFn,
    ) !void {
        const resolver_fn = normalizeResolver(resolver);

        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return error.DependencyAlreadyRegistered;
            }
        }

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        try self.entries.append(self.allocator, .{
            .name = owned_name,
            .resolver = resolver_fn,
            .cleanup = cleanup,
        });
    }

    fn normalizeResolver(resolver: anytype) ResolverFn {
        const T = @TypeOf(resolver);
        if (T == ResolverFn) return resolver;
        if (@typeInfo(T) == .@"fn") {
            const ptr: ResolverFn = &resolver;
            return ptr;
        }
        @compileError("dependency resolver must be fn(*Request, std.mem.Allocator) !?[]const u8");
    }

    fn normalizeCleanup(cleanup: anytype) CleanupFn {
        const T = @TypeOf(cleanup);
        if (T == CleanupFn) return cleanup;
        if (@typeInfo(T) == .@"fn") {
            const ptr: CleanupFn = &cleanup;
            return ptr;
        }
        @compileError(
            "dependency cleanup must be fn(*Request, []const u8, []const u8, std.mem.Allocator) !void",
        );
    }
};

pub const DependencyGraph = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(Dependant) = .empty,
    name_to_index: std.StringHashMapUnmanaged(usize) = .empty,

    const VisitState = enum {
        unvisited,
        visiting,
        done,
    };

    pub const SolveError = error{
        DependencyCycleDetected,
    } || std.mem.Allocator.Error;

    pub fn init(allocator: std.mem.Allocator) DependencyGraph {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DependencyGraph) void {
        self.nodes.deinit(self.allocator);
        self.name_to_index.deinit(self.allocator);
    }

    pub fn add(self: *DependencyGraph, dependant: Dependant) !void {
        if (self.name_to_index.contains(dependant.name)) return;

        const idx = self.nodes.items.len;
        try self.nodes.append(self.allocator, dependant);
        try self.name_to_index.put(self.allocator, dependant.name, idx);
    }

    pub fn solve(self: *const DependencyGraph, allocator: std.mem.Allocator) SolveError![]usize {
        const node_count = self.nodes.items.len;
        if (node_count == 0) return allocator.alloc(usize, 0);

        const states = try allocator.alloc(VisitState, node_count);
        defer allocator.free(states);
        @memset(states, .unvisited);

        var ordered: std.ArrayListUnmanaged(usize) = .empty;
        errdefer ordered.deinit(allocator);

        var idx: usize = 0;
        while (idx < node_count) : (idx += 1) {
            try self.visitNode(allocator, states, &ordered, idx);
        }
        return ordered.toOwnedSlice(allocator);
    }

    fn visitNode(
        self: *const DependencyGraph,
        allocator: std.mem.Allocator,
        states: []VisitState,
        ordered: *std.ArrayListUnmanaged(usize),
        idx: usize,
    ) SolveError!void {
        switch (states[idx]) {
            .done => return,
            .visiting => return error.DependencyCycleDetected,
            .unvisited => {},
        }

        states[idx] = .visiting;

        const node = self.nodes.items[idx];
        for (node.depends_on) |dep_name| {
            const dep_idx = self.name_to_index.get(dep_name) orelse continue;
            try self.visitNode(allocator, states, ordered, dep_idx);
        }

        states[idx] = .done;
        try ordered.append(allocator, idx);
    }
};

test "registry executes dependency and caches value" {
    var registry = Registry.init(std.testing.allocator);
    defer registry.deinit();

    const Resolver = struct {
        fn run(req: *Request, allocator: std.mem.Allocator) !?[]const u8 {
            _ = req;
            _ = allocator;
            return "ok";
        }
    };

    try registry.register("auth", Resolver.run);

    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/", "");
    defer req.deinit();

    try registry.runRouteDependencies(&req, &.{.{ .name = "auth" }}, std.testing.allocator);
    try std.testing.expectEqualStrings("ok", req.dependency("auth").?);
}

test "dependency graph solves deterministically with dependencies first" {
    var graph = DependencyGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.add(.{
        .name = "audit",
        .depends_on = &.{"auth"},
    });
    try graph.add(.{
        .name = "auth",
    });
    try graph.add(.{
        .name = "trace",
        .depends_on = &.{"auth"},
    });

    const order = try graph.solve(std.testing.allocator);
    defer std.testing.allocator.free(order);

    try std.testing.expectEqual(@as(usize, 3), order.len);
    try std.testing.expectEqualStrings("auth", graph.nodes.items[order[0]].name);
    try std.testing.expectEqualStrings("audit", graph.nodes.items[order[1]].name);
    try std.testing.expectEqualStrings("trace", graph.nodes.items[order[2]].name);
}

test "dependency graph detects cycles" {
    var graph = DependencyGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.add(.{
        .name = "a",
        .depends_on = &.{"b"},
    });
    try graph.add(.{
        .name = "b",
        .depends_on = &.{"a"},
    });

    try std.testing.expectError(error.DependencyCycleDetected, graph.solve(std.testing.allocator));
}
