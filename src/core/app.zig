const std = @import("std");
const types = @import("types.zig");
const router_mod = @import("router.zig");
const runtime = @import("../runtime/mod.zig");
const deps = @import("../deps/mod.zig");
const security = @import("../security/mod.zig");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const openapi_gen = @import("../openapi/generator.zig");
const docs_ui = @import("../openapi/docs_ui.zig");
const metrics_registry = @import("metrics_registry.zig");
const observability = @import("observability.zig");
const auth_response = @import("auth_response.zig");
const response_shaping = @import("response_shaping.zig");
const dispatch_helpers = @import("dispatch_helpers.zig");
const state_store = @import("state_store.zig");
const health_mod = @import("../middleware/health.zig");

pub const App = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    include_router_options_arena: std.heap.ArenaAllocator,
    cfg: types.AppConfig,
    router: router_mod.Router,
    dependency_registry: deps.Registry,
    dependency_overrides: deps.Registry,
    state: state_store.Store,
    request_id_counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    shutdown_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    active_server_cfg: ?runtime.ServerConfig = null,
    security_schemes: std.ArrayListUnmanaged(security.NamedScheme) = .empty,
    startup_hooks: std.ArrayListUnmanaged(LifecycleHook) = .empty,
    shutdown_hooks: std.ArrayListUnmanaged(LifecycleHook) = .empty,
    mounted_apps: std.ArrayListUnmanaged(MountEntry) = .empty,
    middleware: std.ArrayListUnmanaged(MiddlewareEntry) = .empty,
    exception_handlers: std.ArrayListUnmanaged(ExceptionHandlerRegistration) = .empty,
    request_customizer: ?RequestCustomizerFn = null,
    telemetry_sink: ?TelemetryFn = null,
    trace_sink: ?TraceFn = null,
    access_log_sink: ?AccessLogFn = null,
    metrics_sink: ?MetricsFn = null,
    audit_sink: ?AuditFn = null,
    unauthorized_handler: ?AuthFailureFn = null,
    insufficient_scope_handler: ?AuthFailureFn = null,
    metrics: metrics_registry.Registry,
    trace_context_header: ?[]u8 = null,
    openapi_cache: ?[]u8 = null,
    docs_cache: ?[]u8 = null,
    redoc_cache: ?[]u8 = null,
    cache_mutex: std.Thread.Mutex = .{},
    health_checks: std.ArrayListUnmanaged(health_mod.HealthCheckEntry) = .empty,
    health_endpoints_enabled: bool = false,

    const LifecycleFn = *const fn () anyerror!void;
    const RequestMiddlewareFn = *const fn (*Request, std.mem.Allocator) anyerror!void;
    const ResponseMiddlewareFn = *const fn (*Request, *Response, std.mem.Allocator) anyerror!void;
    const RequestMiddlewareWithContextFn = *const fn (*Request, std.mem.Allocator, ?*anyopaque) anyerror!void;
    const ResponseMiddlewareWithContextFn = *const fn (*Request, *Response, std.mem.Allocator, ?*anyopaque) anyerror!void;
    const RequestCustomizerFn = *const fn (*Request, std.mem.Allocator) anyerror!void;
    const MiddlewareDeinitFn = *const fn (?*anyopaque, std.mem.Allocator) void;
    const ExceptionHandlerFn = *const fn (*Request, anyerror, std.mem.Allocator) anyerror!Response;
    const TelemetryFn = *const fn (TelemetryEvent, std.mem.Allocator) anyerror!void;
    const TraceFn = *const fn (TraceEvent, std.mem.Allocator) anyerror!void;
    const AccessLogFn = *const fn (AccessLogEvent, std.mem.Allocator) anyerror!void;
    const MetricsFn = *const fn (MetricsEvent, std.mem.Allocator) anyerror!void;
    const AuditFn = *const fn (AuditEvent, std.mem.Allocator) anyerror!void;
    const AuthFailureFn = *const fn (*const Request, std.mem.Allocator) anyerror!Response;

    pub const TelemetryEvent = struct {
        request_id: []const u8,
        correlation_id: []const u8 = "",
        trace_id: []const u8,
        span_id: []const u8,
        method: std.http.Method,
        path: []const u8,
        status: std.http.Status,
        latency_us: u64,
    };

    pub const TraceEvent = struct {
        request_id: []const u8,
        correlation_id: []const u8 = "",
        trace_context: []const u8,
        tracestate: []const u8,
        baggage: []const u8,
        trace_id: []const u8,
        span_id: []const u8,
        method: std.http.Method,
        path: []const u8,
        status: std.http.Status,
        latency_us: u64,
    };

    pub const AccessLogEvent = struct {
        request_id: []const u8,
        correlation_id: []const u8 = "",
        trace_context: []const u8,
        tracestate: []const u8,
        baggage: []const u8,
        trace_id: []const u8,
        span_id: []const u8,
        method: std.http.Method,
        path: []const u8,
        scheme: []const u8,
        host: []const u8,
        status: std.http.Status,
        latency_us: u64,
        remote_addr: []const u8,
        user_agent: []const u8,
    };

    pub const MetricsEvent = struct {
        name: []const u8,
        value: f64,
        method: std.http.Method,
        path: []const u8,
        status: std.http.Status,
        latency_us: u64,
    };

    pub const AuditEvent = struct {
        category: []const u8,
        action: []const u8,
        request_id: []const u8 = "",
        correlation_id: []const u8 = "",
        method: []const u8 = "",
        path: []const u8 = "",
        detail: []const u8 = "",
    };

    pub const Middleware = struct {
        name: []const u8,
        context: ?*anyopaque = null,
        request_hook: ?RequestMiddlewareFn = null,
        response_hook: ?ResponseMiddlewareFn = null,
        request_hook_with_context: ?RequestMiddlewareWithContextFn = null,
        response_hook_with_context: ?ResponseMiddlewareWithContextFn = null,
        deinit_hook: ?MiddlewareDeinitFn = null,
    };

    const LifecycleHook = struct {
        run: LifecycleFn,
    };

    const MountEntry = struct {
        prefix: []u8,
        subapp: *Self,
    };

    const MiddlewareEntry = struct {
        name: []const u8,
        context: ?*anyopaque = null,
        request_hook: ?RequestMiddlewareFn = null,
        response_hook: ?ResponseMiddlewareFn = null,
        request_hook_with_context: ?RequestMiddlewareWithContextFn = null,
        response_hook_with_context: ?ResponseMiddlewareWithContextFn = null,
        deinit_hook: ?MiddlewareDeinitFn = null,
    };

    const ExceptionHandlerRegistration = struct {
        error_names: ?[]const []const u8 = null,
        handler: ExceptionHandlerFn,
    };

    pub fn init(allocator: std.mem.Allocator, cfg: types.AppConfig) !App {
        return .{
            .allocator = allocator,
            .include_router_options_arena = std.heap.ArenaAllocator.init(allocator),
            .cfg = cfg,
            .router = router_mod.Router.init(allocator),
            .dependency_registry = deps.Registry.init(allocator),
            .dependency_overrides = deps.Registry.init(allocator),
            .state = state_store.Store.init(allocator),
            .metrics = metrics_registry.Registry.init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.include_router_options_arena.deinit();
        self.router.deinit();
        self.dependency_registry.deinit();
        self.dependency_overrides.deinit();
        self.metrics.deinit();
        for (self.security_schemes.items) |scheme| self.allocator.free(scheme.name);
        self.security_schemes.deinit(self.allocator);

        self.startup_hooks.deinit(self.allocator);
        self.shutdown_hooks.deinit(self.allocator);
        for (self.mounted_apps.items) |entry| self.allocator.free(entry.prefix);
        self.mounted_apps.deinit(self.allocator);

        for (self.middleware.items) |entry| {
            if (entry.deinit_hook) |hook| hook(entry.context, self.allocator);
            self.allocator.free(entry.name);
        }
        self.middleware.deinit(self.allocator);

        for (self.exception_handlers.items) |item| {
            if (item.error_names) |names| {
                for (names) |name| self.allocator.free(name);
                self.allocator.free(names);
            }
        }
        self.exception_handlers.deinit(self.allocator);

        if (self.trace_context_header) |header| {
            self.allocator.free(header);
            self.trace_context_header = null;
        }

        for (self.health_checks.items) |entry| self.allocator.free(entry.name);
        self.health_checks.deinit(self.allocator);

        self.freeGeneratedCaches();
        self.state.deinit();
    }

    pub fn get(self: *App, path: []const u8, handler: anytype, opts: types.RouteOptions) !void {
        try self.router.addHttpRoute(.GET, path, handler, opts);
        self.invalidateGeneratedCaches();
    }

    pub fn post(self: *App, path: []const u8, handler: anytype, opts: types.RouteOptions) !void {
        try self.router.addHttpRoute(.POST, path, handler, opts);
        self.invalidateGeneratedCaches();
    }

    pub fn put(self: *App, path: []const u8, handler: anytype, opts: types.RouteOptions) !void {
        try self.router.addHttpRoute(.PUT, path, handler, opts);
        self.invalidateGeneratedCaches();
    }

    pub fn patch(self: *App, path: []const u8, handler: anytype, opts: types.RouteOptions) !void {
        try self.router.addHttpRoute(.PATCH, path, handler, opts);
        self.invalidateGeneratedCaches();
    }

    pub fn delete(self: *App, path: []const u8, handler: anytype, opts: types.RouteOptions) !void {
        try self.router.addHttpRoute(.DELETE, path, handler, opts);
        self.invalidateGeneratedCaches();
    }

    pub fn options(self: *App, path: []const u8, handler: anytype, opts: types.RouteOptions) !void {
        try self.router.addHttpRoute(.OPTIONS, path, handler, opts);
        self.invalidateGeneratedCaches();
    }

    pub fn head(self: *App, path: []const u8, handler: anytype, opts: types.RouteOptions) !void {
        try self.router.addHttpRoute(.HEAD, path, handler, opts);
        self.invalidateGeneratedCaches();
    }

    pub fn trace(self: *App, path: []const u8, handler: anytype, opts: types.RouteOptions) !void {
        try self.router.addHttpRoute(.TRACE, path, handler, opts);
        self.invalidateGeneratedCaches();
    }

    pub fn websocket(self: *App, path: []const u8, handler: anytype, opts: types.WebSocketRouteOptions) !void {
        try self.router.addWebSocketRoute(path, handler, opts);
        self.invalidateGeneratedCaches();
    }

    pub fn addDependency(self: *App, name: []const u8, resolver: anytype) !void {
        try self.dependency_registry.register(name, resolver);
    }

    pub fn addDependencyWithCleanup(
        self: *App,
        name: []const u8,
        resolver: anytype,
        cleanup: anytype,
    ) !void {
        try self.dependency_registry.registerWithCleanup(name, resolver, cleanup);
    }

    pub fn overrideDependency(self: *App, name: []const u8, resolver: anytype) !void {
        try self.dependency_overrides.registerOrReplace(name, resolver);
    }

    pub fn overrideDependencyWithCleanup(
        self: *App,
        name: []const u8,
        resolver: anytype,
        cleanup: anytype,
    ) !void {
        try self.dependency_overrides.registerOrReplaceWithCleanup(name, resolver, cleanup);
    }

    pub fn clearDependencyOverride(self: *App, name: []const u8) bool {
        return self.dependency_overrides.remove(name);
    }

    pub fn clearDependencyOverrides(self: *App) void {
        self.dependency_overrides.clear();
    }

    pub fn setStateBorrowed(self: *App, key: []const u8, value: anytype) !void {
        try self.state.setBorrowed(key, state_store.Store.erasePointer(value));
    }

    pub fn setStateOwned(self: *App, key: []const u8, value: anytype, cleanup: anytype) !void {
        try self.state.setOwned(
            key,
            state_store.Store.erasePointer(value),
            state_store.Store.normalizeCleanup(cleanup),
        );
    }

    pub fn removeState(self: *App, key: []const u8) bool {
        return self.state.remove(key);
    }

    pub fn stateAs(self: *App, comptime Ptr: type, key: []const u8) ?Ptr {
        return self.state.getAs(Ptr, key);
    }

    pub fn addSecurityScheme(self: *App, name: []const u8, scheme: security.OpenApiSecurityScheme) !void {
        for (self.security_schemes.items) |*registered| {
            if (std.mem.eql(u8, registered.name, name)) {
                registered.scheme = scheme;
                return;
            }
        }

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        try self.security_schemes.append(self.allocator, .{
            .name = owned_name,
            .scheme = scheme,
        });
        self.invalidateGeneratedCaches();
    }

    pub fn setTelemetrySink(self: *App, sink: anytype) void {
        self.telemetry_sink = normalizeTelemetrySink(sink);
    }

    pub fn setTraceSink(self: *App, sink: anytype) void {
        self.trace_sink = normalizeTraceSink(sink);
    }

    pub fn setAccessLogSink(self: *App, sink: anytype) void {
        self.access_log_sink = normalizeAccessLogSink(sink);
    }

    pub fn setMetricsSink(self: *App, sink: anytype) void {
        self.metrics_sink = normalizeMetricsSink(sink);
    }

    pub fn setAuditSink(self: *App, sink: anytype) void {
        self.audit_sink = normalizeAuditSink(sink);
    }

    pub fn setUnauthorizedHandler(self: *App, handler: anytype) void {
        self.unauthorized_handler = normalizeAuthFailureHandler(handler);
    }

    pub fn setInsufficientScopeHandler(self: *App, handler: anytype) void {
        self.insufficient_scope_handler = normalizeAuthFailureHandler(handler);
    }

    pub fn enableJsonTelemetrySink(self: *App) void {
        self.telemetry_sink = observability.jsonTelemetrySink;
    }

    pub fn enableJsonTraceSink(self: *App) void {
        self.trace_sink = observability.redactedJsonTraceSink;
    }

    pub fn enableJsonAccessLogSink(self: *App) void {
        self.access_log_sink = observability.redactedJsonAccessLogSink;
    }

    pub fn enableJsonMetricsSink(self: *App) void {
        self.metrics_sink = observability.jsonMetricsSink;
    }

    pub fn enableJsonAuditSink(self: *App) void {
        self.audit_sink = observability.jsonAuditSink;
    }

    pub fn setTraceContextHeader(self: *App, header_name: []const u8) !void {
        const owned = try self.allocator.dupe(u8, header_name);
        errdefer self.allocator.free(owned);

        if (self.trace_context_header) |previous| {
            self.allocator.free(previous);
        }
        self.trace_context_header = owned;
    }

    pub fn setRequestCustomizer(self: *App, customizer: anytype) void {
        self.request_customizer = normalizeRequestCustomizer(customizer);
    }

    pub fn setDefaultRouteWrapper(self: *App, wrapper: anytype) void {
        self.router.setDefaultRouteWrapper(wrapper);
    }

    pub fn includeRouter(
        self: *App,
        prefix: []const u8,
        router: *const router_mod.Router,
        opts: types.IncludeRouterOptions,
    ) !void {
        for (router.httpRoutes()) |route| {
            const combined = try dispatch_helpers.joinPaths(self.allocator, prefix, route.path);
            defer self.allocator.free(combined);

            var merged_opts = route.options;
            merged_opts.tags = try self.mergeIncludedTags(route.options.tags, opts.tags);
            merged_opts.dependencies = try self.mergeIncludedDependencies(
                route.options.dependencies,
                opts.dependencies,
            );
            merged_opts.include_in_schema = route.options.include_in_schema and opts.include_in_schema;
            if (merged_opts.default_response_class == null) {
                merged_opts.default_response_class = opts.default_response_class;
            }
            try self.router.addHttpRouteStored(route.method, combined, route.handler, route.wrapper, merged_opts);
        }

        for (router.websocketRoutes()) |route| {
            const combined = try dispatch_helpers.joinPaths(self.allocator, prefix, route.path);
            defer self.allocator.free(combined);

            var merged_ws_opts = route.options;
            merged_ws_opts.dependencies = try self.mergeIncludedDependencies(
                route.options.dependencies,
                opts.dependencies,
            );
            try self.router.addWebSocketRouteStored(
                combined,
                route.handler,
                merged_ws_opts,
                route.injected_dependencies,
            );
        }

        self.invalidateGeneratedCaches();
    }

    pub fn mount(self: *App, prefix: []const u8, subapp: *const App) !void {
        const normalized = try normalizeMountedPrefix(self.allocator, prefix);
        errdefer self.allocator.free(normalized);

        try self.mounted_apps.append(self.allocator, .{
            .prefix = normalized,
            .subapp = @constCast(subapp),
        });
        self.invalidateGeneratedCaches();
    }

    pub fn addMiddleware(self: *App, mw: anytype) !void {
        const T = @TypeOf(mw);

        if (T == Middleware) {
            const name = try self.allocator.dupe(u8, mw.name);
            errdefer self.allocator.free(name);
            try self.middleware.append(self.allocator, .{
                .name = name,
                .context = mw.context,
                .request_hook = mw.request_hook,
                .response_hook = mw.response_hook,
                .request_hook_with_context = mw.request_hook_with_context,
                .response_hook_with_context = mw.response_hook_with_context,
                .deinit_hook = mw.deinit_hook,
            });
            return;
        }

        const name = try self.allocator.dupe(u8, @typeName(T));
        errdefer self.allocator.free(name);

        try self.middleware.append(self.allocator, .{
            .name = name,
            .request_hook = maybeRequestMiddleware(mw),
            .response_hook = maybeResponseMiddleware(mw),
        });
    }

    pub fn addExceptionHandler(self: *App, err_tag: type, handler: anytype) !void {
        const normalized_handler = normalizeExceptionHandler(handler);
        const error_names = try self.ownedErrorSetNames(err_tag);

        try self.exception_handlers.append(self.allocator, .{
            .error_names = error_names,
            .handler = normalized_handler,
        });
    }

    pub fn onStartup(self: *App, handler: anytype) !void {
        try self.startup_hooks.append(self.allocator, .{ .run = normalizeLifecycleHook(handler) });
    }

    pub fn onShutdown(self: *App, handler: anytype) !void {
        try self.shutdown_hooks.append(self.allocator, .{ .run = normalizeLifecycleHook(handler) });
    }

    pub fn lifespan(self: *App, startup: anytype, shutdown: anytype) !void {
        try self.onStartup(startup);
        try self.onShutdown(shutdown);
    }

    /// Register a named health check function for readiness probes.
    pub fn addHealthCheck(self: *App, name: []const u8, check: health_mod.HealthCheckFn) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        try self.health_checks.append(self.allocator, .{
            .name = owned_name,
            .check = check,
        });
    }

    /// Enable the built-in /health/live and /health/ready endpoints.
    pub fn enableHealthEndpoints(self: *App) void {
        self.health_endpoints_enabled = true;
    }

    pub fn requestShutdown(self: *App) void {
        self.shutdown_requested.store(true, .release);
    }

    pub fn isShutdownRequested(self: *const App) bool {
        return self.shutdown_requested.load(.acquire);
    }

    pub fn serve(self: *App, cfg: runtime.ServerConfig) !void {
        self.shutdown_requested.store(false, .release);
        self.active_server_cfg = cfg;
        defer self.active_server_cfg = null;

        self.emitStartupConfigAudit(cfg);
        try self.runStartupLifecycle();

        defer {
            self.runShutdownLifecycle() catch |err| {
                std.log.err("shutdown hook failed: {s}", .{@errorName(err)});
            };
        }

        runtime.server.serve(self, cfg, dispatchTrampoline, self, shouldStopTrampoline) catch |err| {
            self.emitAudit(.{
                .category = "lifecycle",
                .action = "serve_failed",
                .detail = @errorName(err),
            });
            return err;
        };
    }

    pub fn runStartupLifecycle(self: *App) anyerror!void {
        self.emitAudit(.{
            .category = "lifecycle",
            .action = "startup_begin",
        });
        self.runHooks(self.startup_hooks.items) catch |err| {
            self.emitAudit(.{
                .category = "lifecycle",
                .action = "startup_failed",
                .detail = @errorName(err),
            });
            return err;
        };
        self.runMountedStartupHooks() catch |err| {
            self.emitAudit(.{
                .category = "lifecycle",
                .action = "startup_failed",
                .detail = @errorName(err),
            });
            return err;
        };
        self.emitAudit(.{
            .category = "lifecycle",
            .action = "startup_complete",
        });
    }

    pub fn runStartupHooksOnly(self: *App) anyerror!void {
        try self.runHooks(self.startup_hooks.items);
        try self.runMountedStartupHooks();
    }

    pub fn runShutdownLifecycle(self: *App) anyerror!void {
        self.emitAudit(.{
            .category = "lifecycle",
            .action = "shutdown_begin",
        });
        self.runMountedShutdownHooksReverse() catch |err| {
            self.emitAudit(.{
                .category = "lifecycle",
                .action = "shutdown_failed",
                .detail = @errorName(err),
            });
            return err;
        };
        self.runHooksReverse(self.shutdown_hooks.items) catch |err| {
            self.emitAudit(.{
                .category = "lifecycle",
                .action = "shutdown_failed",
                .detail = @errorName(err),
            });
            return err;
        };
        self.emitAudit(.{
            .category = "lifecycle",
            .action = "shutdown_complete",
        });
    }

    pub fn runShutdownHooksOnly(self: *App) anyerror!void {
        try self.runMountedShutdownHooksReverse();
        try self.runHooksReverse(self.shutdown_hooks.items);
    }

    pub fn openapi(self: *App) ![]const u8 {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        if (self.openapi_cache) |doc| return doc;

        const doc = try openapi_gen.generate(
            self.allocator,
            self.cfg,
            self.router.httpRoutes(),
            self.router.websocketRoutes(),
            self.security_schemes.items,
        );
        self.openapi_cache = doc;
        return doc;
    }

    pub fn dispatchSynthetic(self: *App, method: std.http.Method, target: []const u8, body: []const u8) !Response {
        var req = try Request.initSynthetic(self.allocator, method, target, body);
        defer req.deinit();
        defer req.runBackgroundTasks() catch |err| {
            std.log.warn("background task failed: {s}", .{@errorName(err)});
        };
        return self.dispatchWithPipeline(&req);
    }

    pub fn dispatchSyntheticWithHeaders(
        self: *App,
        method: std.http.Method,
        target: []const u8,
        body: []const u8,
        headers: []const std.http.Header,
    ) !Response {
        var req = try Request.initSyntheticWithHeaders(self.allocator, method, target, body, headers);
        defer req.deinit();
        defer req.runBackgroundTasks() catch |err| {
            std.log.warn("background task failed: {s}", .{@errorName(err)});
        };
        return self.dispatchWithPipeline(&req);
    }

    fn dispatchTrampoline(
        ctx: *anyopaque,
        raw_request: *std.http.Server.Request,
        peer_address: std.net.Address,
        socket_fd: std.posix.fd_t,
    ) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ctx));
        try self.handleRawRequest(raw_request, peer_address, socket_fd);
    }

    fn shouldStopTrampoline(ctx: *anyopaque) bool {
        const self: *const App = @ptrCast(@alignCast(ctx));
        return self.shutdown_requested.load(.acquire);
    }

    fn handleRawRequest(
        self: *App,
        raw_request: *std.http.Server.Request,
        peer_address: std.net.Address,
        socket_fd: std.posix.fd_t,
    ) !void {
        const route_guardrails = self.resolveHttpRouteGuardrails(raw_request.head.method, raw_request.head.target);

        const header_limit = route_guardrails.max_header_bytes orelse
            (if (self.active_server_cfg) |cfg| cfg.max_header_bytes else 64 * 1024);
        if (header_limit != 0 and requestHeaderBytes(raw_request) > header_limit) {
            try raw_request.respond("request header too large", .{
                .status = .request_header_fields_too_large,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                },
            });
            return;
        }

        const query_limit = route_guardrails.max_query_bytes orelse
            (if (self.active_server_cfg) |cfg| cfg.max_query_bytes else 16 * 1024);
        if (query_limit != 0 and queryLengthFromTarget(raw_request.head.target) > query_limit) {
            try raw_request.respond("query string too large", .{
                .status = .uri_too_long,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                },
            });
            return;
        }

        const body_limit = route_guardrails.max_body_bytes orelse
            (if (self.active_server_cfg) |cfg| cfg.max_body_bytes else 8 * 1024 * 1024);
        var req = Request.initFromRawWithBodyLimitAndPeer(
            self.allocator,
            raw_request,
            body_limit,
            peer_address,
        ) catch |err| switch (err) {
            error.BodyTooLarge => {
                try raw_request.respond("request body too large", .{
                    .status = .payload_too_large,
                    .extra_headers = &.{
                        .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                    },
                });
                return;
            },
            error.BodyReadTimeout => {
                try raw_request.respond("request body read timeout", .{
                    .status = .request_timeout,
                    .extra_headers = &.{
                        .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                    },
                });
                return;
            },
            else => return err,
        };
        defer req.deinit();
        defer req.runBackgroundTasks() catch |err| {
            std.log.warn("background task failed: {s}", .{@errorName(err)});
        };
        self.prepareRequestContext(&req) catch |err| {
            var prep_response = auth_response.middlewareErrorToResponse(self.allocator, err);
            defer prep_response.deinit(self.allocator);
            try dispatch_helpers.sendResponse(raw_request, self.allocator, &prep_response);
            return;
        };
        self.seedProxyContext(&req);

        if (raw_request.upgradeRequested() == .websocket) {
            const original_path = req.path;
            req.path = self.effectiveRoutePath(req.path);
            defer req.path = original_path;

            if (try self.router.findWebSocket(req.path, &req)) |ws_route| {
                if (self.cfg.request_id_enabled) {
                    try self.ensureRequestId(&req);
                }
                try self.ensureCorrelationId(&req);
                self.ensureTraceContext(&req);
                defer req.runDependencyCleanups(self.allocator) catch |err| {
                    std.log.err("dependency cleanup failed: {s}", .{@errorName(err)});
                };

                const runtime_ws_deps = try self.buildRuntimeDependencies(
                    ws_route.options.dependencies,
                    ws_route.injected_dependencies,
                );
                defer if (runtime_ws_deps.owned) self.allocator.free(runtime_ws_deps.items);

                self.dependency_registry.runRouteDependenciesWithOverrides(
                    &self.dependency_overrides,
                    &req,
                    runtime_ws_deps.items,
                    self.allocator,
                ) catch |err| {
                    switch (err) {
                        error.Unauthorized => self.emitAuthAudit(&req, "websocket_unauthorized", "dependency"),
                        error.InsufficientScope => self.emitAuthAudit(&req, "websocket_insufficient_scope", "dependency"),
                        else => {},
                    }
                    var dep_response = switch (err) {
                        error.Unauthorized => self.unauthorizedResponseForWebSocket(&req, ws_route.options),
                        error.InsufficientScope => self.insufficientScopeResponseForWebSocket(&req, ws_route.options),
                        else => auth_response.dependencyErrorToResponse(self.allocator, err),
                    };
                    defer dep_response.deinit(self.allocator);
                    try dispatch_helpers.sendResponse(raw_request, self.allocator, &dep_response);
                    return;
                };

                if (!dispatch_helpers.isWebSocketOriginAllowed(req.header("origin"), ws_route.options.allowed_origins)) {
                    self.emitAudit(.{
                        .category = "websocket",
                        .action = "origin_rejected",
                        .request_id = req.requestId() orelse "",
                        .correlation_id = req.correlationId() orelse "",
                        .method = @tagName(req.method),
                        .path = req.path,
                        .detail = "origin not allowed",
                    });
                    try raw_request.respond("websocket origin not allowed", .{
                        .status = .forbidden,
                        .extra_headers = &.{
                            .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                        },
                    });
                    return;
                }

                const selected_subprotocol = dispatch_helpers.selectWebSocketSubprotocol(
                    req.header("sec-websocket-protocol"),
                    ws_route.options.subprotocols,
                );
                if (ws_route.options.subprotocols.len > 0 and
                    ws_route.options.require_subprotocol and
                    selected_subprotocol == null)
                {
                    self.emitAudit(.{
                        .category = "websocket",
                        .action = "subprotocol_rejected",
                        .request_id = req.requestId() orelse "",
                        .correlation_id = req.correlationId() orelse "",
                        .method = @tagName(req.method),
                        .path = req.path,
                        .detail = "required subprotocol missing or unsupported",
                    });
                    try raw_request.respond("websocket subprotocol required", .{
                        .status = .bad_request,
                        .extra_headers = &.{
                            .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                        },
                    });
                    return;
                }

                const maybe_key = raw_request.upgradeRequested().websocket;
                const key = maybe_key orelse {
                    try raw_request.respond("missing sec-websocket-key", .{
                        .status = .bad_request,
                        .extra_headers = &.{
                            .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
                        },
                    });
                    return;
                };

                var handshake_headers: [1]std.http.Header = undefined;
                const extra_headers: []const std.http.Header = if (selected_subprotocol) |subprotocol| blk: {
                    handshake_headers[0] = .{
                        .name = "sec-websocket-protocol",
                        .value = subprotocol,
                    };
                    break :blk handshake_headers[0..1];
                } else &.{};

                var ws = try raw_request.respondWebSocket(.{
                    .key = key,
                    .extra_headers = extra_headers,
                });
                var conn = runtime.websocket.Connection.initWithSocket(&ws, socket_fd);
                conn.setIdleTimeoutMs(ws_route.options.idle_timeout_ms);
                conn.setAutoPong(ws_route.options.auto_pong);
                conn.setPingPolicy(
                    ws_route.options.ping_interval_ms,
                    ws_route.options.pong_timeout_ms,
                );
                conn.setMaxMessageBytes(ws_route.options.max_message_bytes);
                conn.setSendTimeoutMs(ws_route.options.send_timeout_ms);
                conn.setNegotiatedSubprotocol(selected_subprotocol);
                defer conn.deinit(self.allocator);
                ws_route.handler(&conn, &req, self.allocator) catch |err| {
                    std.log.warn("websocket handler failed: {s}", .{@errorName(err)});
                };
                return;
            }
        }

        var response = try self.dispatchWithPipeline(&req);
        defer response.deinit(self.allocator);

        try dispatch_helpers.sendResponse(raw_request, self.allocator, &response);
    }

    fn queryLengthFromTarget(target: []const u8) usize {
        const qmark_idx = std.mem.indexOfScalar(u8, target, '?') orelse return 0;
        const rest = target[qmark_idx + 1 ..];
        const fragment_idx = std.mem.indexOfScalar(u8, rest, '#') orelse return rest.len;
        return rest[0..fragment_idx].len;
    }

    const RouteGuardrails = struct {
        max_header_bytes: ?usize = null,
        max_query_bytes: ?usize = null,
        max_body_bytes: ?usize = null,
    };

    const RuntimeDependencies = struct {
        items: []const types.DependencySpec,
        owned: bool = false,
    };

    fn resolveHttpRouteGuardrails(self: *App, method: std.http.Method, target: []const u8) RouteGuardrails {
        var probe = Request.initSynthetic(self.allocator, method, target, "") catch return .{};
        defer probe.deinit();

        const route = self.router.findHttp(&probe) catch return .{};
        if (route) |matched| {
            return .{
                .max_header_bytes = matched.options.max_header_bytes,
                .max_query_bytes = matched.options.max_query_bytes,
                .max_body_bytes = matched.options.max_body_bytes,
            };
        }
        return .{};
    }

    fn requestHeaderBytes(raw_request: *std.http.Server.Request) usize {
        var total: usize = @tagName(raw_request.head.method).len +
            1 +
            raw_request.head.target.len +
            " HTTP/1.1\r\n".len;

        var headers = raw_request.iterateHeaders();
        while (headers.next()) |header| {
            total += header.name.len + 2 + header.value.len + 2;
        }

        total += 2;
        return total;
    }

    fn dispatchWithPipeline(self: *App, req: *Request) !Response {
        self.prepareRequestContext(req) catch |err| {
            return auth_response.middlewareErrorToResponse(self.allocator, err);
        };
        if (self.cfg.request_id_enabled) {
            try self.ensureRequestId(req);
        }
        try self.ensureCorrelationId(req);
        self.ensureTraceContext(req);
        const start_ns = std.time.nanoTimestamp();

        self.runRequestMiddleware(req) catch |err| {
            var response = auth_response.middlewareErrorToResponse(self.allocator, err);
            self.finalizeResponse(req, &response, start_ns);
            return response;
        };

        var response = self.dispatchCoreWithPrefix(req, null) catch |err| {
            std.log.warn("dispatch failed: {s}", .{@errorName(err)});
            var fallback = Response.text("internal server error").withStatus(.internal_server_error);
            self.finalizeResponse(req, &fallback, start_ns);
            return fallback;
        };
        errdefer response.deinit(self.allocator);

        self.runResponseMiddleware(req, &response) catch |err| {
            response.deinit(self.allocator);
            var fallback = auth_response.middlewareErrorToResponse(self.allocator, err);
            self.finalizeResponse(req, &fallback, start_ns);
            return fallback;
        };

        self.finalizeResponse(req, &response, start_ns);
        return response;
    }

    fn dispatchNestedWithinParent(self: *App, req: *Request, public_prefix: ?[]const u8) !Response {
        self.prepareRequestContext(req) catch |err| {
            return auth_response.middlewareErrorToResponse(self.allocator, err);
        };

        self.runRequestMiddleware(req) catch |err| {
            return auth_response.middlewareErrorToResponse(self.allocator, err);
        };

        var response = try self.dispatchCoreWithPrefix(req, public_prefix);
        errdefer response.deinit(self.allocator);

        self.runResponseMiddleware(req, &response) catch |err| {
            response.deinit(self.allocator);
            return auth_response.middlewareErrorToResponse(self.allocator, err);
        };

        return response;
    }

    fn dispatchCore(self: *App, req: *Request) !Response {
        return self.dispatchCoreWithPrefix(req, null);
    }

    fn dispatchCoreWithPrefix(self: *App, req: *Request, public_prefix: ?[]const u8) !Response {
        const original_path = req.path;
        req.path = self.effectiveRoutePath(req.path);
        defer req.path = original_path;

        if (self.cfg.openapi_url) |openapi_url| {
            if (std.mem.eql(u8, req.path, openapi_url)) {
                const doc = try self.openapi();
                return .{
                    .status = .ok,
                    .body = doc,
                    .content_type = "application/json",
                };
            }
        }

        if (self.cfg.docs_url) |docs_url| {
            if (std.mem.eql(u8, req.path, docs_url)) {
                const html = try self.docsHtml(public_prefix);
                return .{
                    .status = .ok,
                    .body = html,
                    .owned_body = if (public_prefix != null) html else null,
                    .content_type = "text/html; charset=utf-8",
                };
            }
        }

        if (self.cfg.redoc_url) |redoc_url| {
            if (std.mem.eql(u8, req.path, redoc_url)) {
                const html = try self.redocHtml(public_prefix);
                return .{
                    .status = .ok,
                    .body = html,
                    .owned_body = if (public_prefix != null) html else null,
                    .content_type = "text/html; charset=utf-8",
                };
            }
        }

        if (self.cfg.metrics_url) |metrics_url| {
            if (req.method == .GET and std.mem.eql(u8, req.path, metrics_url)) {
                const payload = try self.metrics.renderPrometheus(self.allocator);
                return .{
                    .status = .ok,
                    .body = payload,
                    .owned_body = payload,
                    .content_type = "text/plain; version=0.0.4; charset=utf-8",
                };
            }
        }

        if (self.health_endpoints_enabled and req.method == .GET) {
            if (std.mem.eql(u8, req.path, "/health/live")) {
                const result = try health_mod.liveResponse(self.allocator);
                return .{
                    .status = result.status,
                    .body = result.body,
                    .owned_body = result.body,
                    .content_type = "application/json",
                };
            }
            if (std.mem.eql(u8, req.path, "/health/ready")) {
                const result = try health_mod.readyResponse(self.allocator, self.health_checks.items);
                return .{
                    .status = result.status,
                    .body = result.body,
                    .owned_body = result.body,
                    .content_type = "application/json",
                };
            }
        }

        if (try self.router.findHttp(req)) |route| {
            req.setDependencyValueBorrowed("zigmund.route.path_template", route.path) catch |err| {
                std.log.warn("failed to set route template dependency: {s}", .{@errorName(err)});
            };
            self.seedRouteValidationMode(req, route.options);
            self.seedRouteResponseContext(req, route.options);
            defer req.runDependencyCleanups(self.allocator) catch |err| {
                std.log.err("dependency cleanup failed: {s}", .{@errorName(err)});
            };

            const runtime_deps = try self.buildRuntimeDependencies(
                route.options.dependencies,
                route.options.injected_dependencies,
            );
            defer if (runtime_deps.owned) self.allocator.free(runtime_deps.items);

            self.dependency_registry.runRouteDependenciesWithOverrides(
                &self.dependency_overrides,
                req,
                runtime_deps.items,
                self.allocator,
            ) catch |err| {
                if (err == error.Unauthorized) {
                    self.emitAuthAudit(req, "http_unauthorized", "dependency");
                    return self.unauthorizedResponseForRoute(req, route.options);
                }
                if (err == error.InsufficientScope) {
                    self.emitAuthAudit(req, "http_insufficient_scope", "dependency");
                    return self.insufficientScopeResponseForRoute(req, route.options);
                }
                return auth_response.dependencyErrorToResponse(self.allocator, err);
            };

            var route_response = self.executeHttpRoute(route, req) catch |err| {
                if (err == error.ValidationFailed and req.hasValidationIssues()) {
                    return dispatch_helpers.validationIssuesToResponse(self.allocator, req.validationIssues());
                }
                if (err == error.UnsupportedMediaType) {
                    return Response.text("unsupported media type").withStatus(.unsupported_media_type);
                }
                if (err == error.Unauthorized) {
                    self.emitAuthAudit(req, "http_unauthorized", "handler");
                    return self.unauthorizedResponseForRoute(req, route.options);
                }
                if (err == error.InsufficientScope) {
                    self.emitAuthAudit(req, "http_insufficient_scope", "handler");
                    return self.insufficientScopeResponseForRoute(req, route.options);
                }
                if (err == error.DependencyCycleDetected) {
                    return Response.text("dependency cycle detected").withStatus(.internal_server_error);
                }
                if (self.lookupExceptionHandler(err)) |entry| {
                    return entry.handler(req, err, self.allocator) catch |handler_err| {
                        std.log.warn(
                            "exception handler failed for {s}: {s}",
                            .{ @errorName(err), @errorName(handler_err) },
                        );
                        return Response.text("internal server error").withStatus(.internal_server_error);
                    };
                }

                std.log.warn("unhandled route error: {s}", .{@errorName(err)});
                return Response.text("internal server error").withStatus(.internal_server_error);
            };

            self.applyResponseModelShaping(route.options, &route_response) catch |err| {
                std.log.warn("response shaping failed: {s}", .{@errorName(err)});
                route_response.deinit(self.allocator);
                return Response.text("internal server error").withStatus(.internal_server_error);
            };
            return route_response;
        }

        for (self.mounted_apps.items) |entry| {
            const sub_path = mountedSubPath(req.path, entry.prefix) orelse continue;
            const mounted_prefix = try self.allocMountedPublicPrefix(entry.prefix, public_prefix);
            defer self.allocator.free(mounted_prefix);

            const mounted_original_path = req.path;
            req.path = sub_path;
            defer req.path = mounted_original_path;

            return entry.subapp.dispatchNestedWithinParent(req, mounted_prefix);
        }

        if (self.cfg.redirect_slashes) {
            if (try self.redirectSlashResponse(req, original_path, public_prefix)) |response| {
                return response;
            }
        }

        return Response.text("not found").withStatus(.not_found);
    }

    fn seedRouteValidationMode(self: *const App, req: *Request, route_options: types.StoredRouteOptions) void {
        const strict_enabled = route_options.strict_validation orelse self.cfg.strict_validation;
        req.setDependencyValueBorrowed("zigmund.validation.strict", if (strict_enabled) "true" else "false") catch |err| {
            std.log.warn("failed to set validation strict mode dependency: {s}", .{@errorName(err)});
        };
    }

    fn seedRouteResponseContext(self: *const App, req: *Request, route_options: types.StoredRouteOptions) void {
        _ = self;

        if (route_options.default_response_class) |class_name| {
            req.setDependencyValueBorrowed("zigmund.route.default_response_class", class_name) catch |err| {
                std.log.warn("failed to set route response class dependency: {s}", .{@errorName(err)});
            };
        }

        if (route_options.status_code) |status_code| {
            var buf: [8]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d}", .{@intFromEnum(status_code)}) catch return;
            req.setDependencyValue("zigmund.route.status_code", rendered) catch |err| {
                std.log.warn("failed to set route status dependency: {s}", .{@errorName(err)});
            };
        }
    }

    fn seedProxyContext(self: *const App, req: *Request) void {
        const cfg = self.active_server_cfg orelse return;
        const info = runtime.extractProxyInfoWithConfig(req, cfg);

        if (info.client_ip) |client_ip| {
            req.setDependencyValueBorrowed("client_ip", client_ip) catch |err| {
                std.log.warn("failed to set client_ip dependency: {s}", .{@errorName(err)});
            };
            req.setDependencyValueBorrowed("zigmund.proxy.client_ip", client_ip) catch |err| {
                std.log.warn("failed to set zigmund.proxy.client_ip dependency: {s}", .{@errorName(err)});
            };
        }

        if (info.proto) |proto| {
            req.setDependencyValueBorrowed("scheme", proto) catch |err| {
                std.log.warn("failed to set scheme dependency: {s}", .{@errorName(err)});
            };
            req.setDependencyValueBorrowed("zigmund.proxy.proto", proto) catch |err| {
                std.log.warn("failed to set zigmund.proxy.proto dependency: {s}", .{@errorName(err)});
            };
        }

        if (info.host) |host| {
            req.setDependencyValueBorrowed("host", host) catch |err| {
                std.log.warn("failed to set host dependency: {s}", .{@errorName(err)});
            };
            req.setDependencyValueBorrowed("zigmund.proxy.host", host) catch |err| {
                std.log.warn("failed to set zigmund.proxy.host dependency: {s}", .{@errorName(err)});
            };
        }
    }

    fn mergeIncludedTags(
        self: *App,
        route_tags: []const []const u8,
        include_tags: []const []const u8,
    ) ![]const []const u8 {
        const total = include_tags.len + route_tags.len;
        if (total == 0) return &.{};

        const allocator = self.include_router_options_arena.allocator();
        const merged = try allocator.alloc([]const u8, total);

        var idx: usize = 0;
        for (include_tags) |tag| {
            merged[idx] = tag;
            idx += 1;
        }
        for (route_tags) |tag| {
            merged[idx] = tag;
            idx += 1;
        }
        return merged;
    }

    fn buildRuntimeDependencies(
        self: *App,
        route_dependencies: []const types.DependencySpec,
        injected_dependencies: []const types.DependencySpec,
    ) !RuntimeDependencies {
        var injected_registered_count: usize = 0;
        for (injected_dependencies) |dep| {
            if (self.dependency_registry.lookup(dep.name) != null) injected_registered_count += 1;
        }

        if (injected_registered_count == 0) {
            return .{
                .items = route_dependencies,
                .owned = false,
            };
        }

        if (route_dependencies.len == 0 and injected_registered_count == injected_dependencies.len) {
            return .{
                .items = injected_dependencies,
                .owned = false,
            };
        }

        const count = route_dependencies.len + injected_registered_count;
        if (count == 0) {
            return .{
                .items = &.{},
                .owned = false,
            };
        }

        const merged = try self.allocator.alloc(types.DependencySpec, count);
        var idx: usize = 0;

        for (route_dependencies) |dep| {
            merged[idx] = dep;
            idx += 1;
        }

        for (injected_dependencies) |dep| {
            if (self.dependency_registry.lookup(dep.name) == null) continue;
            merged[idx] = dep;
            idx += 1;
        }

        return .{
            .items = merged,
            .owned = true,
        };
    }

    fn mergeIncludedDependencies(
        self: *App,
        route_dependencies: []const types.DependencySpec,
        include_dependencies: []const types.DependencySpec,
    ) ![]const types.DependencySpec {
        const total = include_dependencies.len + route_dependencies.len;
        if (total == 0) return &.{};

        const allocator = self.include_router_options_arena.allocator();
        const merged = try allocator.alloc(types.DependencySpec, total);

        var idx: usize = 0;
        for (include_dependencies) |dep| {
            merged[idx] = dep;
            idx += 1;
        }
        for (route_dependencies) |dep| {
            merged[idx] = dep;
            idx += 1;
        }
        return merged;
    }

    fn lookupExceptionHandler(self: *const App, err: anyerror) ?ExceptionHandlerRegistration {
        const err_name = @errorName(err);
        var wildcard: ?ExceptionHandlerRegistration = null;

        for (self.exception_handlers.items) |entry| {
            if (entry.error_names) |names| {
                for (names) |name| {
                    if (std.mem.eql(u8, name, err_name)) return entry;
                }
            } else if (wildcard == null) {
                wildcard = entry;
            }
        }

        return wildcard;
    }

    fn ownedErrorSetNames(self: *App, comptime ErrSet: type) !?[]const []const u8 {
        if (@typeInfo(ErrSet) != .error_set) {
            @compileError("addExceptionHandler err_tag must be an error set type (e.g. error{MyError})");
        }

        const set_info = @typeInfo(ErrSet).error_set;
        if (set_info == null) return null;
        const members = set_info.?;

        const names = try self.allocator.alloc([]const u8, members.len);
        errdefer self.allocator.free(names);
        var initialized: usize = 0;
        errdefer {
            for (names[0..initialized]) |name| self.allocator.free(name);
        }

        for (members) |member| {
            names[initialized] = try self.allocator.dupe(u8, member.name);
            initialized += 1;
        }

        return names;
    }

    fn normalizeExceptionHandler(handler: anytype) ExceptionHandlerFn {
        const T = @TypeOf(handler);
        if (T == ExceptionHandlerFn) return handler;
        if (@typeInfo(T) != .@"fn") {
            @compileError("Exception handler must be a function");
        }

        if (comptime isDirectExceptionHandlerType(T)) {
            const ptr: ExceptionHandlerFn = &handler;
            return ptr;
        }

        if (comptime isRequestOnlyExceptionHandlerType(T)) {
            const Adapter = struct {
                fn run(req: *Request, _: anyerror, allocator: std.mem.Allocator) anyerror!Response {
                    return @call(.auto, handler, .{ req, allocator });
                }
            };
            return Adapter.run;
        }

        @compileError(
            "Exception handler must be fn(*Request, anyerror, std.mem.Allocator) Response/!Response or fn(*Request, std.mem.Allocator) Response/!Response",
        );
    }

    fn isDirectExceptionHandlerType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 3) return false;
        if (info.params[0].type != *Request) return false;
        if (info.params[1].type != anyerror) return false;
        if (info.params[2].type != std.mem.Allocator) return false;
        return isResponseOrErrorResponse(info.return_type orelse return false);
    }

    fn isRequestOnlyExceptionHandlerType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != *Request) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        return isResponseOrErrorResponse(info.return_type orelse return false);
    }

    fn isResponseOrErrorResponse(comptime T: type) bool {
        if (T == Response) return true;
        if (@typeInfo(T) != .error_union) return false;
        return @typeInfo(T).error_union.payload == Response;
    }

    fn runHooks(self: *App, hooks: []const LifecycleHook) anyerror!void {
        _ = self;
        for (hooks) |hook| try hook.run();
    }

    fn runHooksReverse(self: *App, hooks: []const LifecycleHook) anyerror!void {
        _ = self;
        var idx = hooks.len;
        while (idx > 0) {
            idx -= 1;
            try hooks[idx].run();
        }
    }

    fn runMountedStartupHooks(self: *App) anyerror!void {
        for (self.mounted_apps.items) |entry| {
            try entry.subapp.runStartupHooksOnly();
        }
    }

    fn runMountedShutdownHooksReverse(self: *App) anyerror!void {
        var idx = self.mounted_apps.items.len;
        while (idx > 0) {
            idx -= 1;
            try self.mounted_apps.items[idx].subapp.runShutdownHooksOnly();
        }
    }

    pub fn prepareRequestContext(self: *App, req: *Request) !void {
        req.attachAppState(&self.state);
        req.attachDependencyOverrideLookup(@ptrCast(&self.dependency_overrides), dependencyOverrideLookup);
        if (self.request_customizer) |customizer| {
            try customizer(req, self.allocator);
        }
    }

    pub fn effectiveRoutePath(self: *const App, path: []const u8) []const u8 {
        const root_path = self.normalizedRootPath() orelse return path;
        if (!std.mem.startsWith(u8, path, root_path)) return path;
        if (path.len == root_path.len) return "/";
        if (path[root_path.len] != '/') return path;
        return path[root_path.len..];
    }

    fn executeHttpRoute(self: *App, route: *const router_mod.HttpRoute, req: *Request) anyerror!Response {
        if (route.wrapper) |wrapper| {
            return wrapper(req, route.handler, self.allocator);
        }
        return route.handler(req, self.allocator);
    }

    fn runRequestMiddleware(self: *App, req: *Request) !void {
        for (self.middleware.items) |entry| {
            if (entry.request_hook_with_context) |hook| {
                try hook(req, self.allocator, entry.context);
                continue;
            }
            if (entry.request_hook) |hook| {
                try hook(req, self.allocator);
            }
        }
    }

    fn runResponseMiddleware(self: *App, req: *Request, response: *Response) !void {
        for (self.middleware.items) |entry| {
            if (entry.response_hook_with_context) |hook| {
                try hook(req, response, self.allocator, entry.context);
                continue;
            }
            if (entry.response_hook) |hook| {
                try hook(req, response, self.allocator);
            }
        }
    }

    fn normalizeRequestCustomizer(customizer: anytype) RequestCustomizerFn {
        const T = @TypeOf(customizer);
        if (T == RequestCustomizerFn) return customizer;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isRequestCustomizerType(T)) {
                const ptr: RequestCustomizerFn = &customizer;
                return ptr;
            }
        }
        @compileError("Request customizer must be fn(*Request, std.mem.Allocator) !void");
    }

    fn isRequestCustomizerType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != *Request) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        if (info.return_type == null) return false;

        const ret = info.return_type.?;
        if (@typeInfo(ret) == .error_union) {
            return @typeInfo(ret).error_union.payload == void;
        }
        return ret == void;
    }

    fn ensureRequestId(self: *App, req: *Request) !void {
        const request_id_header = self.requestIdHeaderName();
        if (req.requestId() == null) {
            if (req.header(request_id_header)) |incoming| {
                if (incoming.len != 0) {
                    req.setRequestIdBorrowed(incoming);
                }
            }
        }

        if (req.requestId() == null) {
            const next_id = self.request_id_counter.fetchAdd(1, .monotonic) + 1;
            var generated_buf: [32]u8 = undefined;
            const generated = try std.fmt.bufPrint(
                &generated_buf,
                "req-{x}",
                .{next_id},
            );
            try req.setRequestIdInline(generated);
        }

        if (req.requestId()) |request_id| {
            req.setDependencyValueBorrowed("request_id", request_id) catch |err| {
                std.log.warn("failed to set request_id dependency: {s}", .{@errorName(err)});
            };
        }
    }

    fn requestIdHeaderName(self: *const App) []const u8 {
        if (self.cfg.request_id_header.len == 0) return "x-request-id";
        return self.cfg.request_id_header;
    }

    fn correlationIdHeaderName(self: *const App) []const u8 {
        if (self.cfg.correlation_id_header.len == 0) return "x-correlation-id";
        return self.cfg.correlation_id_header;
    }

    fn ensureCorrelationId(self: *App, req: *Request) !void {
        const correlation_header = self.correlationIdHeaderName();
        if (req.correlationId() == null) {
            if (req.header(correlation_header)) |incoming| {
                if (incoming.len != 0) {
                    req.setCorrelationIdBorrowed(incoming);
                }
            }
        }

        if (req.correlationId() == null) {
            // Fall back to request ID as correlation ID
            if (req.requestId()) |rid| {
                try req.setCorrelationIdInline(rid);
            } else {
                const next_id = self.request_id_counter.fetchAdd(1, .monotonic) + 1;
                var generated_buf: [32]u8 = undefined;
                const generated = try std.fmt.bufPrint(
                    &generated_buf,
                    "corr-{x}",
                    .{next_id},
                );
                try req.setCorrelationIdInline(generated);
            }
        }

        if (req.correlationId()) |cid| {
            req.setDependencyValueBorrowed("correlation_id", cid) catch |err| {
                std.log.warn("failed to set correlation_id dependency: {s}", .{@errorName(err)});
            };
        }
    }

    fn ensureTraceContext(self: *App, req: *Request) void {
        const header_name = self.trace_context_header orelse "traceparent";
        const trace_context = req.header(header_name) orelse req.header("x-correlation-id") orelse return;
        if (trace_context.len == 0) return;

        req.setDependencyValueBorrowed("trace_context", trace_context) catch |err| {
            std.log.warn("failed to set trace_context dependency: {s}", .{@errorName(err)});
        };
        if (req.header("tracestate")) |tracestate| {
            if (tracestate.len != 0) {
                req.setDependencyValueBorrowed("tracestate", tracestate) catch |err| {
                    std.log.warn("failed to set tracestate dependency: {s}", .{@errorName(err)});
                };
            }
        }
        if (req.header("baggage")) |baggage| {
            if (baggage.len != 0) {
                req.setDependencyValueBorrowed("baggage", baggage) catch |err| {
                    std.log.warn("failed to set baggage dependency: {s}", .{@errorName(err)});
                };
            }
        }

        if (parseTraceparent(trace_context)) |parsed| {
            req.setDependencyValueBorrowed("trace_id", parsed.trace_id) catch |err| {
                std.log.warn("failed to set trace_id dependency: {s}", .{@errorName(err)});
            };
            req.setDependencyValueBorrowed("span_id", parsed.span_id) catch |err| {
                std.log.warn("failed to set span_id dependency: {s}", .{@errorName(err)});
            };
            req.setDependencyValueBorrowed("trace_flags", parsed.trace_flags) catch |err| {
                std.log.warn("failed to set trace_flags dependency: {s}", .{@errorName(err)});
            };
        }
    }

    const TraceIdentity = struct {
        trace_context: []const u8,
        tracestate: []const u8,
        baggage: []const u8,
        trace_id: []const u8,
        span_id: []const u8,
    };

    const ParsedTraceparent = struct {
        trace_id: []const u8,
        span_id: []const u8,
        trace_flags: []const u8,
    };

    fn buildTraceIdentity(req: *const Request) TraceIdentity {
        return .{
            .trace_context = req.dependency("trace_context") orelse "",
            .tracestate = req.dependency("tracestate") orelse "",
            .baggage = req.dependency("baggage") orelse "",
            .trace_id = req.dependency("trace_id") orelse "",
            .span_id = req.dependency("span_id") orelse "",
        };
    }

    fn parseTraceparent(raw_value: []const u8) ?ParsedTraceparent {
        const value = std.mem.trim(u8, raw_value, " \t");
        if (value.len != 55) return null;
        if (value[2] != '-' or value[35] != '-' or value[52] != '-') return null;

        const version = value[0..2];
        const trace_id = value[3..35];
        const span_id = value[36..52];
        const trace_flags = value[53..55];

        if (!allHex(version) or !allHex(trace_id) or !allHex(span_id) or !allHex(trace_flags)) return null;
        if (allZeros(trace_id) or allZeros(span_id)) return null;

        return .{
            .trace_id = trace_id,
            .span_id = span_id,
            .trace_flags = trace_flags,
        };
    }

    fn allHex(value: []const u8) bool {
        for (value) |ch| {
            if (!std.ascii.isHex(ch)) return false;
        }
        return true;
    }

    fn allZeros(value: []const u8) bool {
        for (value) |ch| {
            if (ch != '0') return false;
        }
        return true;
    }

    fn finalizeResponse(self: *App, req: *Request, response: *Response, start_ns: i128) void {
        if (self.cfg.request_id_enabled) {
            self.attachRequestIdHeader(req, response);
        }
        self.attachCorrelationIdHeader(req, response);
        const latency_us = observability.elapsedMicros(start_ns);
        self.emitTelemetry(req, response.status, latency_us);
        self.emitTrace(req, response.status, latency_us);
        self.emitAccessLog(req, response.status, latency_us);
        self.emitMetrics(req, response.status, latency_us);
    }

    fn attachRequestIdHeader(self: *App, req: *Request, response: *Response) void {
        const request_id_header = self.requestIdHeaderName();
        if (response.hasHeader(request_id_header)) return;
        const request_id = req.requestId() orelse return;
        response.setHeader(self.allocator, request_id_header, request_id) catch |err| {
            std.log.warn("failed to set request id header: {s}", .{@errorName(err)});
        };
    }

    fn attachCorrelationIdHeader(self: *App, req: *const Request, response: *Response) void {
        const correlation_id_header = self.correlationIdHeaderName();
        if (response.hasHeader(correlation_id_header)) return;
        const correlation_id = req.correlationId() orelse return;
        response.setHeader(self.allocator, correlation_id_header, correlation_id) catch |err| {
            std.log.warn("failed to set correlation id header: {s}", .{@errorName(err)});
        };
    }

    fn emitTelemetry(self: *const App, req: *const Request, status: std.http.Status, latency_us: u64) void {
        if (self.telemetry_sink == null and !self.cfg.structured_telemetry_logs) return;

        const trace_identity = buildTraceIdentity(req);
        const path = observability.observabilityPath(req);
        const event: TelemetryEvent = .{
            .request_id = req.requestId() orelse "",
            .correlation_id = req.correlationId() orelse "",
            .trace_id = trace_identity.trace_id,
            .span_id = trace_identity.span_id,
            .method = req.method,
            .path = path,
            .status = status,
            .latency_us = latency_us,
        };

        if (self.telemetry_sink) |sink| {
            sink(event, self.allocator) catch |err| {
                std.log.warn("telemetry sink failed: {s}", .{@errorName(err)});
            };
            return;
        }

        if (self.cfg.structured_telemetry_logs) {
            observability.jsonTelemetrySink(event, self.allocator) catch |err| {
                std.log.warn("telemetry json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn emitTrace(self: *const App, req: *const Request, status: std.http.Status, latency_us: u64) void {
        if (self.trace_sink == null and !self.cfg.structured_trace_logs) return;

        const trace_identity = buildTraceIdentity(req);
        const path = observability.observabilityPath(req);
        const event: TraceEvent = .{
            .request_id = req.requestId() orelse "",
            .correlation_id = req.correlationId() orelse "",
            .trace_context = trace_identity.trace_context,
            .tracestate = trace_identity.tracestate,
            .baggage = trace_identity.baggage,
            .trace_id = trace_identity.trace_id,
            .span_id = trace_identity.span_id,
            .method = req.method,
            .path = path,
            .status = status,
            .latency_us = latency_us,
        };

        if (self.trace_sink) |sink| {
            sink(event, self.allocator) catch |err| {
                std.log.warn("trace sink failed: {s}", .{@errorName(err)});
            };
            return;
        }

        if (self.cfg.structured_trace_logs) {
            observability.jsonTraceSink(self.redactedTraceEvent(event), self.allocator) catch |err| {
                std.log.warn("trace json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn emitAccessLog(self: *const App, req: *const Request, status: std.http.Status, latency_us: u64) void {
        if (self.access_log_sink == null and !self.cfg.structured_access_logs) return;

        var addr_buf: [128]u8 = undefined;
        const remote_addr = req.dependency("zigmund.proxy.client_ip") orelse
            (if (req.peerAddress()) |peer|
                std.fmt.bufPrint(&addr_buf, "{f}", .{peer}) catch ""
            else
                "");
        const scheme = req.dependency("zigmund.proxy.proto") orelse
            (if (self.active_server_cfg) |cfg|
                if (cfg.tls != null) "https" else "http"
            else
                "");
        const host = req.dependency("zigmund.proxy.host") orelse req.header("host") orelse "";
        const trace_identity = buildTraceIdentity(req);
        const path = observability.observabilityPath(req);

        const event: AccessLogEvent = .{
            .request_id = req.requestId() orelse "",
            .correlation_id = req.correlationId() orelse "",
            .trace_context = trace_identity.trace_context,
            .tracestate = trace_identity.tracestate,
            .baggage = trace_identity.baggage,
            .trace_id = trace_identity.trace_id,
            .span_id = trace_identity.span_id,
            .method = req.method,
            .path = path,
            .scheme = scheme,
            .host = host,
            .status = status,
            .latency_us = latency_us,
            .remote_addr = remote_addr,
            .user_agent = req.header("user-agent") orelse "",
        };

        if (self.access_log_sink) |sink| {
            sink(event, self.allocator) catch |err| {
                std.log.warn("access log sink failed: {s}", .{@errorName(err)});
            };
            return;
        }

        if (self.cfg.structured_access_logs) {
            observability.jsonAccessLogSink(self.redactedAccessLogEvent(event), self.allocator) catch |err| {
                std.log.warn("access log json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn emitMetrics(self: *App, req: *const Request, status: std.http.Status, latency_us: u64) void {
        const collect_registry = self.cfg.metrics_url != null;
        const emit_sink_or_logs = self.metrics_sink != null or self.cfg.structured_metrics_logs;
        if (!collect_registry and !emit_sink_or_logs) return;
        const path = observability.observabilityPath(req);

        if (collect_registry) {
            self.metrics.observe(req.method, path, status, latency_us) catch |err| {
                std.log.warn("metrics registry observe failed: {s}", .{@errorName(err)});
            };
        }

        const count_event: MetricsEvent = .{
            .name = "zigmund_http_requests_total",
            .value = 1,
            .method = req.method,
            .path = path,
            .status = status,
            .latency_us = latency_us,
        };

        const latency_event: MetricsEvent = .{
            .name = "zigmund_http_request_latency_us",
            .value = @as(f64, @floatFromInt(latency_us)),
            .method = req.method,
            .path = path,
            .status = status,
            .latency_us = latency_us,
        };

        if (!emit_sink_or_logs) return;

        if (self.metrics_sink) |sink| {
            sink(count_event, self.allocator) catch |err| {
                std.log.warn("metrics sink failed: {s}", .{@errorName(err)});
                return;
            };
            sink(latency_event, self.allocator) catch |err| {
                std.log.warn("metrics sink failed: {s}", .{@errorName(err)});
            };
            return;
        }

        if (self.cfg.structured_metrics_logs) {
            observability.jsonMetricsSink(count_event, self.allocator) catch |err| {
                std.log.warn("metrics json sink failed: {s}", .{@errorName(err)});
            };
            observability.jsonMetricsSink(latency_event, self.allocator) catch |err| {
                std.log.warn("metrics json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn redactedTraceEvent(self: *const App, event: TraceEvent) TraceEvent {
        return observability.redactTraceEvent(event, .{
            .marker = self.structuredLogRedactionText(),
            .redact_tracestate = self.cfg.structured_log_redact_tracestate,
            .redact_baggage = self.cfg.structured_log_redact_baggage,
        });
    }

    fn redactedAccessLogEvent(self: *const App, event: AccessLogEvent) AccessLogEvent {
        return observability.redactAccessLogEvent(event, .{
            .marker = self.structuredLogRedactionText(),
            .redact_tracestate = self.cfg.structured_log_redact_tracestate,
            .redact_baggage = self.cfg.structured_log_redact_baggage,
            .redact_remote_addr = self.cfg.structured_log_redact_remote_addr,
            .redact_user_agent = self.cfg.structured_log_redact_user_agent,
        });
    }

    fn structuredLogRedactionText(self: *const App) []const u8 {
        if (self.cfg.structured_log_redaction_text.len == 0) return "[redacted]";
        return self.cfg.structured_log_redaction_text;
    }

    fn emitAudit(self: *const App, event: AuditEvent) void {
        if (self.audit_sink) |sink| {
            sink(event, self.allocator) catch |err| {
                std.log.warn("audit sink failed: {s}", .{@errorName(err)});
            };
            return;
        }

        if (self.cfg.structured_audit_logs) {
            observability.jsonAuditSink(event, self.allocator) catch |err| {
                std.log.warn("audit json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn emitStartupConfigAudit(self: *App, cfg: runtime.ServerConfig) void {
        const detail = std.fmt.allocPrint(
            self.allocator,
            "{{\"host\":{f},\"port\":{d},\"workers\":{d},\"recv_buffer_size\":{d},\"send_buffer_size\":{d},\"reuse_address\":{},\"max_header_bytes\":{d},\"max_query_bytes\":{d},\"max_body_bytes\":{d},\"max_connections\":{d},\"overload_retry_after_seconds\":{d},\"accept_poll_interval_ms\":{d},\"header_timeout_ms\":{d},\"body_timeout_ms\":{d},\"write_timeout_ms\":{d},\"idle_timeout_ms\":{d},\"shutdown_grace_period_ms\":{d},\"trusted_proxy_headers\":{},\"trusted_proxy_forwarded_header\":{},\"trusted_proxy_x_forwarded_headers\":{},\"trusted_proxy_cidrs\":{d},\"tls_enabled\":{}}}",
            .{
                std.json.fmt(cfg.host, .{}),
                cfg.port,
                cfg.resolvedWorkerCount(),
                cfg.recv_buffer_size,
                cfg.send_buffer_size,
                cfg.reuse_address,
                cfg.max_header_bytes,
                cfg.max_query_bytes,
                cfg.max_body_bytes,
                cfg.max_connections,
                cfg.overload_retry_after_seconds,
                cfg.accept_poll_interval_ms,
                cfg.header_timeout_ms,
                cfg.body_timeout_ms,
                cfg.write_timeout_ms,
                cfg.idle_timeout_ms,
                cfg.shutdown_grace_period_ms,
                cfg.trusted_proxy_headers,
                cfg.trusted_proxy_forwarded_header,
                cfg.trusted_proxy_x_forwarded_headers,
                cfg.trusted_proxy_cidrs.len,
                cfg.tls != null,
            },
        ) catch |err| {
            std.log.warn("failed to format startup audit detail: {s}", .{@errorName(err)});
            return;
        };
        defer self.allocator.free(detail);

        self.emitAudit(.{
            .category = "lifecycle",
            .action = "startup_config",
            .detail = detail,
        });
    }

    fn emitAuthAudit(self: *App, req: *const Request, action: []const u8, detail: []const u8) void {
        self.emitAudit(.{
            .category = "auth",
            .action = action,
            .request_id = req.requestId() orelse "",
            .correlation_id = req.correlationId() orelse "",
            .method = @tagName(req.method),
            .path = req.path,
            .detail = detail,
        });
    }

    fn applyResponseModelShaping(
        self: *App,
        route_options: types.StoredRouteOptions,
        response: *Response,
    ) !void {
        if (route_options.response_model_name == null) return;
        if (!response_shaping.needsResponseShaping(route_options)) return;
        if (!dispatch_helpers.isJsonContentType(response.content_type)) return;

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response.body, .{}) catch return;
        defer parsed.deinit();

        var shaped = parsed.value;
        if (route_options.response_model_transform) |transform| {
            try transform(&shaped, self.allocator);
        }
        try response_shaping.applyResponseModelFieldFilter(
            self.allocator,
            &shaped,
            route_options.response_model_field_rules,
        );

        try response_shaping.applyTopLevelIncludeExclude(
            self.allocator,
            &shaped,
            route_options.response_model_include,
            route_options.response_model_exclude,
        );

        if (route_options.response_model_exclude_defaults) {
            try response_shaping.applyExcludeDefaults(
                &shaped,
                route_options.response_model_field_rules,
            );
        }

        if (route_options.response_model_exclude_none) {
            try response_shaping.pruneNullValues(self.allocator, &shaped);
        }

        if (route_options.response_model_by_alias) {
            try response_shaping.applyResponseModelAliases(
                self.allocator,
                &shaped,
                route_options.response_model_field_rules,
            );
        }

        if (route_options.response_model_validate) |validate| {
            try validate(&shaped, self.allocator);
        }

        const payload = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(shaped, .{})});
        if (response.owned_body) |body| self.allocator.free(body);
        response.body = payload;
        response.owned_body = payload;
    }

    fn dependencyOverrideLookup(ctx: ?*anyopaque, key: []const u8) ?Request.DependencyOverride {
        const registry_ptr = ctx orelse return null;
        const registry: *const deps.Registry = @ptrCast(@alignCast(registry_ptr));
        const resolved = registry.lookupResolved(key) orelse return null;
        return .{
            .resolver = resolved.resolver,
            .cleanup = resolved.cleanup,
        };
    }

    fn unauthorizedResponseForRoute(
        self: *const App,
        req: *const Request,
        route_options: types.StoredRouteOptions,
    ) Response {
        return self.buildUnauthorizedResponse(
            req,
            self.unauthorized_handler,
            self.routeSecurityChallenge(route_options),
            self.routeSecurityStyle(route_options),
        );
    }

    fn unauthorizedResponseForWebSocket(
        self: *const App,
        req: *const Request,
        route_options: types.WebSocketRouteOptions,
    ) Response {
        return self.buildUnauthorizedResponse(
            req,
            self.unauthorized_handler,
            self.dependenciesSecurityChallenge(route_options.dependencies),
            self.dependenciesSecurityStyle(route_options.dependencies),
        );
    }

    fn insufficientScopeResponseForRoute(
        self: *const App,
        req: *const Request,
        route_options: types.StoredRouteOptions,
    ) Response {
        return self.buildInsufficientScopeResponse(
            req,
            self.insufficient_scope_handler,
            self.routeSecurityChallenge(route_options),
            self.routeSecurityStyle(route_options),
            self.routeRequiredScopes(route_options),
        );
    }

    fn insufficientScopeResponseForWebSocket(
        self: *const App,
        req: *const Request,
        route_options: types.WebSocketRouteOptions,
    ) Response {
        return self.buildInsufficientScopeResponse(
            req,
            self.insufficient_scope_handler,
            self.dependenciesSecurityChallenge(route_options.dependencies),
            self.dependenciesSecurityStyle(route_options.dependencies),
            self.dependenciesRequiredScopes(route_options.dependencies) orelse &.{},
        );
    }

    /// Shared logic for building unauthorized responses (Route and WebSocket).
    fn buildUnauthorizedResponse(
        self: *const App,
        req: *const Request,
        custom_handler: ?AuthFailureFn,
        security_challenge: ?[]const u8,
        security_style: SecurityAuthStyle,
    ) Response {
        if (custom_handler) |handler| {
            return handler(req, self.allocator) catch |err| {
                std.log.warn("unauthorized handler failed: {s}", .{@errorName(err)});
                return Response.text("internal server error").withStatus(.internal_server_error);
            };
        }

        const status: std.http.Status = if (security_style == .api_key) .forbidden else .unauthorized;
        var response = Response.text(if (status == .forbidden) "forbidden" else "unauthorized").withStatus(status);

        if (security_challenge) |challenge| {
            response.setHeader(self.allocator, "www-authenticate", challenge) catch |err| {
                std.log.debug("failed to set header: {s}", .{@errorName(err)});
            };
        } else if (security_style != .api_key) {
            response.setHeader(self.allocator, "www-authenticate", "Bearer") catch |err| {
                std.log.debug("failed to set header: {s}", .{@errorName(err)});
            };
        }
        return response;
    }

    /// Shared logic for building insufficient-scope responses (Route and WebSocket).
    fn buildInsufficientScopeResponse(
        self: *const App,
        req: *const Request,
        custom_handler: ?AuthFailureFn,
        security_challenge: ?[]const u8,
        security_style: SecurityAuthStyle,
        required_scopes: []const []const u8,
    ) Response {
        if (custom_handler) |handler| {
            return handler(req, self.allocator) catch |err| {
                std.log.warn("insufficient-scope handler failed: {s}", .{@errorName(err)});
                return Response.text("internal server error").withStatus(.internal_server_error);
            };
        }

        if (security_challenge == null and security_style == .api_key) {
            return Response.text("forbidden").withStatus(.forbidden);
        }
        const challenge_base = security_challenge orelse "Bearer";

        var response = Response.text("forbidden").withStatus(.forbidden);

        if (std.ascii.eqlIgnoreCase(challenge_base, "bearer")) {
            var challenge_buf: std.ArrayList(u8) = .empty;
            defer challenge_buf.deinit(self.allocator);

            var writer = challenge_buf.writer(self.allocator);
            writer.writeAll("Bearer error=\"insufficient_scope\"") catch {
                response.setHeader(
                    self.allocator,
                    "www-authenticate",
                    "Bearer error=\"insufficient_scope\"",
                ) catch |err| {
                    std.log.debug("failed to set header: {s}", .{@errorName(err)});
                };
                return response;
            };

            if (required_scopes.len > 0) {
                writer.writeAll(", scope=\"") catch |err| {
                    std.log.debug("failed to set header: {s}", .{@errorName(err)});
                };
                for (required_scopes, 0..) |scope, idx| {
                    if (idx != 0) writer.writeByte(' ') catch |err| {
                        std.log.debug("failed to set header: {s}", .{@errorName(err)});
                    };
                    writer.writeAll(scope) catch |err| {
                        std.log.debug("failed to set header: {s}", .{@errorName(err)});
                    };
                }
                writer.writeByte('"') catch |err| {
                    std.log.debug("failed to set header: {s}", .{@errorName(err)});
                };
            }

            const challenge = challenge_buf.toOwnedSlice(self.allocator) catch {
                response.setHeader(
                    self.allocator,
                    "www-authenticate",
                    "Bearer error=\"insufficient_scope\"",
                ) catch |err| {
                    std.log.debug("failed to set header: {s}", .{@errorName(err)});
                };
                return response;
            };
            defer self.allocator.free(challenge);
            response.setHeader(self.allocator, "www-authenticate", challenge) catch |err| {
                std.log.debug("failed to set header: {s}", .{@errorName(err)});
            };
            return response;
        }

        response.setHeader(self.allocator, "www-authenticate", challenge_base) catch |err| {
            std.log.debug("failed to set header: {s}", .{@errorName(err)});
        };
        return response;
    }

    fn routeSecurityChallenge(self: *const App, route_options: types.StoredRouteOptions) ?[]const u8 {
        if (self.dependenciesSecurityChallenge(route_options.dependencies)) |challenge| return challenge;
        if (self.dependenciesSecurityChallenge(route_options.injected_dependencies)) |challenge| return challenge;
        return null;
    }

    const SecurityAuthStyle = enum {
        unknown,
        api_key,
        challenge,
    };

    fn routeSecurityStyle(self: *const App, route_options: types.StoredRouteOptions) SecurityAuthStyle {
        const route_style = self.dependenciesSecurityStyle(route_options.dependencies);
        if (route_style != .unknown) return route_style;
        return self.dependenciesSecurityStyle(route_options.injected_dependencies);
    }

    fn routeRequiredScopes(self: *const App, route_options: types.StoredRouteOptions) []const []const u8 {
        if (self.dependenciesRequiredScopes(route_options.dependencies)) |scopes| return scopes;
        if (self.dependenciesRequiredScopes(route_options.injected_dependencies)) |scopes| return scopes;
        return &.{};
    }

    fn dependenciesSecurityChallenge(
        self: *const App,
        dependencies: []const types.DependencySpec,
    ) ?[]const u8 {
        for (dependencies) |dep| {
            const scheme = self.lookupSecurityScheme(dep.name) orelse continue;
            if (auth_response.challengeForSecurityScheme(scheme.scheme)) |challenge| return challenge;
        }
        return null;
    }

    fn dependenciesSecurityStyle(
        self: *const App,
        dependencies: []const types.DependencySpec,
    ) SecurityAuthStyle {
        for (dependencies) |dep| {
            const scheme = self.lookupSecurityScheme(dep.name) orelse continue;
            return switch (scheme.scheme) {
                .api_key => .api_key,
                else => .challenge,
            };
        }
        return .unknown;
    }

    fn dependenciesRequiredScopes(
        self: *const App,
        dependencies: []const types.DependencySpec,
    ) ?[]const []const u8 {
        for (dependencies) |dep| {
            if (dep.scopes.len == 0) continue;
            if (self.lookupSecurityScheme(dep.name) != null) return dep.scopes;
            if (std.mem.startsWith(u8, dep.name, "security_")) return dep.scopes;
        }
        return null;
    }

    fn lookupSecurityScheme(self: *const App, name: []const u8) ?security.NamedScheme {
        for (self.security_schemes.items) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }

    /// Generic sink type checker: returns true if T is fn(EventType, std.mem.Allocator) void/!void.
    fn isSinkType(comptime EventType: type, comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != EventType) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        return isVoidOrErrorVoid(info.return_type orelse return false);
    }

    /// Generic sink normalizer: coerces a bare function to the expected pointer type.
    fn normalizeSinkFn(comptime FnType: type, comptime EventType: type, sink: anytype) FnType {
        const T = @TypeOf(sink);
        if (T == FnType) return sink;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isSinkType(EventType, T)) {
                const ptr: FnType = &sink;
                return ptr;
            }
        }
        @compileError("invalid sink type");
    }

    fn normalizeTelemetrySink(sink: anytype) TelemetryFn {
        return normalizeSinkFn(TelemetryFn, TelemetryEvent, sink);
    }

    fn normalizeTraceSink(sink: anytype) TraceFn {
        return normalizeSinkFn(TraceFn, TraceEvent, sink);
    }

    fn normalizeAccessLogSink(sink: anytype) AccessLogFn {
        return normalizeSinkFn(AccessLogFn, AccessLogEvent, sink);
    }

    fn normalizeMetricsSink(sink: anytype) MetricsFn {
        return normalizeSinkFn(MetricsFn, MetricsEvent, sink);
    }

    fn normalizeAuditSink(sink: anytype) AuditFn {
        return normalizeSinkFn(AuditFn, AuditEvent, sink);
    }

    fn normalizeAuthFailureHandler(handler: anytype) AuthFailureFn {
        const T = @TypeOf(handler);
        if (T == AuthFailureFn) return handler;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isAuthFailureHandlerType(T)) {
                const ptr: AuthFailureFn = &handler;
                return ptr;
            }
        }
        @compileError("Auth failure handler must be fn(*const Request, std.mem.Allocator) !Response");
    }

    fn isAuthFailureHandlerType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != *const Request) return false;
        if (info.params[1].type != std.mem.Allocator) return false;

        const return_type = info.return_type orelse return false;
        if (@typeInfo(return_type) != .error_union) return false;
        return @typeInfo(return_type).error_union.payload == Response;
    }

    fn docsHtml(self: *App, public_prefix: ?[]const u8) ![]u8 {
        if (public_prefix != null) {
            return self.renderDocsHtml(public_prefix);
        }

        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        if (self.docs_cache) |html| return html;
        const html = try self.renderDocsHtml(null);
        self.docs_cache = html;
        return html;
    }

    fn redocHtml(self: *App, public_prefix: ?[]const u8) ![]u8 {
        if (public_prefix != null) {
            return self.renderRedocHtml(public_prefix);
        }

        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        if (self.redoc_cache) |html| return html;
        const html = try self.renderRedocHtml(null);
        self.redoc_cache = html;
        return html;
    }

    fn renderDocsHtml(self: *App, public_prefix: ?[]const u8) ![]u8 {
        const openapi_url = try self.allocPublicPathWithPrefix(self.cfg.openapi_url orelse "/openapi.json", public_prefix);
        defer self.allocator.free(openapi_url);
        return docs_ui.renderSwagger(
            self.allocator,
            self.cfg.title,
            openapi_url,
            self.cfg.docs,
        );
    }

    fn renderRedocHtml(self: *App, public_prefix: ?[]const u8) ![]u8 {
        const openapi_url = try self.allocPublicPathWithPrefix(self.cfg.openapi_url orelse "/openapi.json", public_prefix);
        defer self.allocator.free(openapi_url);
        return docs_ui.renderRedoc(
            self.allocator,
            self.cfg.title,
            openapi_url,
            self.cfg.redoc,
        );
    }

    fn invalidateGeneratedCaches(self: *App) void {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        self.freeGeneratedCachesLocked();
    }

    fn freeGeneratedCaches(self: *App) void {
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        self.freeGeneratedCachesLocked();
    }

    /// Must be called with cache_mutex held.
    fn freeGeneratedCachesLocked(self: *App) void {
        if (self.openapi_cache) |doc| {
            self.allocator.free(doc);
            self.openapi_cache = null;
        }
        if (self.docs_cache) |html| {
            self.allocator.free(html);
            self.docs_cache = null;
        }
        if (self.redoc_cache) |html| {
            self.allocator.free(html);
            self.redoc_cache = null;
        }
    }

    fn normalizeLifecycleHook(handler: anytype) LifecycleFn {
        const T = @TypeOf(handler);
        if (T == LifecycleFn) return handler;
        if (@typeInfo(T) == .@"fn") {
            const ptr: LifecycleFn = &handler;
            return ptr;
        }
        @compileError("Lifecycle hook must be fn() !void");
    }

    fn normalizedRootPath(self: *const App) ?[]const u8 {
        const configured = self.cfg.root_path orelse return null;
        if (configured.len == 0 or configured[0] != '/') return null;

        var end = configured.len;
        while (end > 1 and configured[end - 1] == '/') {
            end -= 1;
        }

        const normalized = configured[0..end];
        if (std.mem.eql(u8, normalized, "/")) return null;
        return normalized;
    }

    fn allocPublicPath(self: *App, path: []const u8) ![]u8 {
        return self.allocPublicPathWithPrefix(path, null);
    }

    fn allocPublicPathWithPrefix(self: *App, path: []const u8, public_prefix: ?[]const u8) ![]u8 {
        const root_path = self.normalizedRootPath();
        if (public_prefix == null and root_path == null) {
            return self.allocator.dupe(u8, path);
        }

        var prefix_buf = std.ArrayList(u8).empty;
        defer prefix_buf.deinit(self.allocator);

        if (public_prefix) |prefix| {
            try prefix_buf.appendSlice(self.allocator, prefix);
        }
        if (root_path) |root| {
            const combined = if (prefix_buf.items.len == 0)
                try self.allocator.dupe(u8, root)
            else
                try dispatch_helpers.joinPaths(self.allocator, prefix_buf.items, root);
            defer self.allocator.free(combined);
            prefix_buf.clearRetainingCapacity();
            try prefix_buf.appendSlice(self.allocator, combined);
        }

        return dispatch_helpers.joinPaths(self.allocator, prefix_buf.items, path);
    }

    fn allocMountedPublicPrefix(self: *App, mount_prefix: []const u8, public_prefix: ?[]const u8) ![]u8 {
        if (public_prefix) |prefix| {
            return dispatch_helpers.joinPaths(self.allocator, prefix, mount_prefix);
        }
        if (self.normalizedRootPath()) |root| {
            return dispatch_helpers.joinPaths(self.allocator, root, mount_prefix);
        }
        return self.allocator.dupe(u8, mount_prefix);
    }

    fn normalizeMountedPrefix(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
        if (prefix.len == 0 or prefix[0] != '/') return error.InvalidPath;
        var end = prefix.len;
        while (end > 1 and prefix[end - 1] == '/') {
            end -= 1;
        }
        return allocator.dupe(u8, prefix[0..end]);
    }

    fn mountedSubPath(path: []const u8, prefix: []const u8) ?[]const u8 {
        if (!std.mem.startsWith(u8, path, prefix)) return null;
        if (path.len == prefix.len) return "/";
        if (prefix.len == 1) return path;
        if (path[prefix.len] != '/') return null;
        return path[prefix.len..];
    }

    fn redirectSlashResponse(self: *App, req: *Request, original_public_path: []const u8, public_prefix: ?[]const u8) !?Response {
        _ = public_prefix;
        if (req.path.len <= 1) return null;

        const alternate_internal = if (std.mem.endsWith(u8, req.path, "/"))
            req.path[0 .. req.path.len - 1]
        else
            try std.fmt.allocPrint(self.allocator, "{s}/", .{req.path});
        defer if (!std.mem.endsWith(u8, req.path, "/")) self.allocator.free(alternate_internal);

        if (!try self.hasDispatchTarget(req.method, alternate_internal)) return null;

        const alternate_public = if (std.mem.endsWith(u8, original_public_path, "/"))
            original_public_path[0 .. original_public_path.len - 1]
        else
            try std.fmt.allocPrint(self.allocator, "{s}/", .{original_public_path});
        defer if (!std.mem.endsWith(u8, original_public_path, "/")) self.allocator.free(alternate_public);

        const location = if (req.query.len == 0)
            alternate_public
        else
            try std.fmt.allocPrint(self.allocator, "{s}?{s}", .{ alternate_public, req.query });
        defer if (req.query.len != 0) self.allocator.free(location);

        return try Response.redirect(self.allocator, location, .temporary_redirect);
    }

    fn hasDispatchTarget(self: *App, method: std.http.Method, path: []const u8) !bool {
        const target = try self.allocator.dupe(u8, path);
        defer self.allocator.free(target);

        var probe = try Request.initSynthetic(self.allocator, method, target, "");
        defer probe.deinit();
        return self.hasDispatchTargetProbe(&probe);
    }

    fn hasDispatchTargetProbe(self: *App, req: *Request) !bool {
        const original_path = req.path;
        req.path = self.effectiveRoutePath(req.path);
        defer req.path = original_path;

        if (self.cfg.openapi_url) |openapi_url| {
            if (std.mem.eql(u8, req.path, openapi_url)) return true;
        }
        if (self.cfg.docs_url) |docs_url| {
            if (std.mem.eql(u8, req.path, docs_url)) return true;
        }
        if (self.cfg.redoc_url) |redoc_url| {
            if (std.mem.eql(u8, req.path, redoc_url)) return true;
        }
        if (self.cfg.metrics_url) |metrics_url| {
            if (req.method == .GET and std.mem.eql(u8, req.path, metrics_url)) return true;
        }
        if (self.health_endpoints_enabled and req.method == .GET) {
            if (std.mem.eql(u8, req.path, "/health/live") or std.mem.eql(u8, req.path, "/health/ready")) return true;
        }
        if (try self.router.findHttp(req)) |_| return true;

        for (self.mounted_apps.items) |entry| {
            const sub_path = mountedSubPath(req.path, entry.prefix) orelse continue;
            const mounted_original_path = req.path;
            req.path = sub_path;
            defer req.path = mounted_original_path;
            return entry.subapp.hasDispatchTargetProbe(req);
        }

        return false;
    }

    fn maybeRequestMiddleware(mw: anytype) ?RequestMiddlewareFn {
        const T = @TypeOf(mw);
        if (T == RequestMiddlewareFn) return mw;
        if (comptime isRequestMiddlewareType(T)) {
            const ptr: RequestMiddlewareFn = &mw;
            return ptr;
        }
        return null;
    }

    fn maybeResponseMiddleware(mw: anytype) ?ResponseMiddlewareFn {
        const T = @TypeOf(mw);
        if (T == ResponseMiddlewareFn) return mw;
        if (comptime isResponseMiddlewareType(T)) {
            const ptr: ResponseMiddlewareFn = &mw;
            return ptr;
        }
        return null;
    }

    fn isRequestMiddlewareType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != *Request) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        return isVoidOrErrorVoid(info.return_type orelse return false);
    }

    fn isResponseMiddlewareType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 3) return false;
        if (info.params[0].type != *Request) return false;
        if (info.params[1].type != *Response) return false;
        if (info.params[2].type != std.mem.Allocator) return false;
        return isVoidOrErrorVoid(info.return_type orelse return false);
    }

    fn isVoidOrErrorVoid(comptime T: type) bool {
        if (T == void) return true;
        if (@typeInfo(T) != .error_union) return false;
        return @typeInfo(T).error_union.payload == void;
    }
};

test "openapi endpoint works in synthetic dispatch" {
    var app = try App.init(std.testing.allocator, .{ .title = "Zigmund", .version = "0.1.0" });
    defer app.deinit();

    const H = struct {
        fn handler(req: *Request, allocator: std.mem.Allocator) !Response {
            _ = req;
            return Response.json(allocator, .{ .ok = true });
        }
    };

    try app.get("/health", H.handler, .{ .summary = "Health check" });

    var res = try app.dispatchSynthetic(.GET, "/openapi.json", "");
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"/health\"") != null);
}

test "proxy context seeds request dependencies from trusted headers" {
    var app = try App.init(std.testing.allocator, .{
        .title = "proxy-context",
        .version = "0.0.1",
    });
    defer app.deinit();

    app.active_server_cfg = .{
        .trusted_proxy_headers = true,
        .trusted_proxy_forwarded_header = false,
        .trusted_proxy_x_forwarded_headers = true,
    };
    defer app.active_server_cfg = null;

    const headers = [_]std.http.Header{
        .{ .name = "forwarded", .value = "for=203.0.113.43;proto=https;host=api.example.com" },
        .{ .name = "x-forwarded-for", .value = "198.51.100.10" },
        .{ .name = "x-forwarded-proto", .value = "http" },
        .{ .name = "x-forwarded-host", .value = "edge.example.net" },
    };
    var req = try Request.initSyntheticWithHeaders(std.testing.allocator, .GET, "/proxy", "", &headers);
    defer req.deinit();

    app.seedProxyContext(&req);

    try std.testing.expectEqualStrings("198.51.100.10", req.dependency("client_ip").?);
    try std.testing.expectEqualStrings("http", req.dependency("scheme").?);
    try std.testing.expectEqualStrings("edge.example.net", req.dependency("host").?);
    try std.testing.expectEqualStrings("198.51.100.10", req.dependency("zigmund.proxy.client_ip").?);
    try std.testing.expectEqualStrings("http", req.dependency("zigmund.proxy.proto").?);
    try std.testing.expectEqualStrings("edge.example.net", req.dependency("zigmund.proxy.host").?);
}

test "access log remote address prefers trusted proxy client ip dependency" {
    const Capture = struct {
        var remote_addr: ?[]u8 = null;
        var scheme: ?[]u8 = null;
        var host: ?[]u8 = null;

        fn reset(allocator: std.mem.Allocator) void {
            if (remote_addr) |value| allocator.free(value);
            remote_addr = null;
            if (scheme) |value| allocator.free(value);
            scheme = null;
            if (host) |value| allocator.free(value);
            host = null;
        }

        fn sink(event: App.AccessLogEvent, allocator: std.mem.Allocator) !void {
            reset(allocator);
            remote_addr = try allocator.dupe(u8, event.remote_addr);
            scheme = try allocator.dupe(u8, event.scheme);
            host = try allocator.dupe(u8, event.host);
        }
    };

    var app = try App.init(std.testing.allocator, .{
        .title = "proxy-access-log",
        .version = "0.0.1",
    });
    defer app.deinit();
    defer Capture.reset(std.testing.allocator);
    app.setAccessLogSink(Capture.sink);

    var req = try Request.initSynthetic(std.testing.allocator, .GET, "/logs", "");
    defer req.deinit();
    req.setPeerAddress(std.net.Address.initIp4(.{ 198, 51, 100, 44 }, 8080));
    try req.setDependencyValueBorrowed("zigmund.proxy.client_ip", "203.0.113.9");
    try req.setDependencyValueBorrowed("zigmund.proxy.proto", "https");
    try req.setDependencyValueBorrowed("zigmund.proxy.host", "api.example.com");

    app.emitAccessLog(&req, .ok, 12);
    try std.testing.expectEqualStrings("203.0.113.9", Capture.remote_addr.?);
    try std.testing.expectEqualStrings("https", Capture.scheme.?);
    try std.testing.expectEqualStrings("api.example.com", Capture.host.?);
}
