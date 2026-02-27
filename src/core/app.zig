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

pub const App = struct {
    allocator: std.mem.Allocator,
    include_router_options_arena: std.heap.ArenaAllocator,
    cfg: types.AppConfig,
    router: router_mod.Router,
    dependency_registry: deps.Registry,
    request_id_counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    shutdown_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    active_server_cfg: ?runtime.ServerConfig = null,
    security_schemes: std.ArrayListUnmanaged(security.NamedScheme) = .empty,
    startup_hooks: std.ArrayListUnmanaged(LifecycleHook) = .empty,
    shutdown_hooks: std.ArrayListUnmanaged(LifecycleHook) = .empty,
    middleware: std.ArrayListUnmanaged(MiddlewareEntry) = .empty,
    exception_handlers: std.ArrayListUnmanaged(ExceptionHandlerRegistration) = .empty,
    telemetry_sink: ?TelemetryFn = null,
    trace_sink: ?TraceFn = null,
    access_log_sink: ?AccessLogFn = null,
    metrics_sink: ?MetricsFn = null,
    audit_sink: ?AuditFn = null,
    metrics: metrics_registry.Registry,
    trace_context_header: ?[]u8 = null,
    openapi_cache: ?[]u8 = null,
    docs_cache: ?[]u8 = null,
    redoc_cache: ?[]u8 = null,

    const LifecycleFn = *const fn () anyerror!void;
    const RequestMiddlewareFn = *const fn (*Request, std.mem.Allocator) anyerror!void;
    const ResponseMiddlewareFn = *const fn (*Request, *Response, std.mem.Allocator) anyerror!void;
    const ExceptionHandlerFn = *const fn (*Request, anyerror, std.mem.Allocator) anyerror!Response;
    const TelemetryFn = *const fn (TelemetryEvent, std.mem.Allocator) anyerror!void;
    const TraceFn = *const fn (TraceEvent, std.mem.Allocator) anyerror!void;
    const AccessLogFn = *const fn (AccessLogEvent, std.mem.Allocator) anyerror!void;
    const MetricsFn = *const fn (MetricsEvent, std.mem.Allocator) anyerror!void;
    const AuditFn = *const fn (AuditEvent, std.mem.Allocator) anyerror!void;

    pub const TelemetryEvent = struct {
        request_id: []const u8,
        trace_id: []const u8,
        span_id: []const u8,
        method: std.http.Method,
        path: []const u8,
        status: std.http.Status,
        latency_us: u64,
    };

    pub const TraceEvent = struct {
        request_id: []const u8,
        trace_context: []const u8,
        trace_id: []const u8,
        span_id: []const u8,
        method: std.http.Method,
        path: []const u8,
        status: std.http.Status,
        latency_us: u64,
    };

    pub const AccessLogEvent = struct {
        request_id: []const u8,
        trace_context: []const u8,
        trace_id: []const u8,
        span_id: []const u8,
        method: std.http.Method,
        path: []const u8,
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
        method: []const u8 = "",
        path: []const u8 = "",
        detail: []const u8 = "",
    };

    pub const Middleware = struct {
        name: []const u8,
        request_hook: ?RequestMiddlewareFn = null,
        response_hook: ?ResponseMiddlewareFn = null,
    };

    const LifecycleHook = struct {
        run: LifecycleFn,
    };

    const MiddlewareEntry = struct {
        name: []const u8,
        request_hook: ?RequestMiddlewareFn = null,
        response_hook: ?ResponseMiddlewareFn = null,
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
            .metrics = metrics_registry.Registry.init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.include_router_options_arena.deinit();
        self.router.deinit();
        self.dependency_registry.deinit();
        self.metrics.deinit();
        for (self.security_schemes.items) |scheme| self.allocator.free(scheme.name);
        self.security_schemes.deinit(self.allocator);

        self.startup_hooks.deinit(self.allocator);
        self.shutdown_hooks.deinit(self.allocator);

        for (self.middleware.items) |entry| self.allocator.free(entry.name);
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

        self.freeGeneratedCaches();
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

    pub fn enableJsonTelemetrySink(self: *App) void {
        self.telemetry_sink = jsonTelemetrySink;
    }

    pub fn enableJsonTraceSink(self: *App) void {
        self.trace_sink = jsonTraceSink;
    }

    pub fn enableJsonAccessLogSink(self: *App) void {
        self.access_log_sink = jsonAccessLogSink;
    }

    pub fn enableJsonMetricsSink(self: *App) void {
        self.metrics_sink = jsonMetricsSink;
    }

    pub fn enableJsonAuditSink(self: *App) void {
        self.audit_sink = jsonAuditSink;
    }

    pub fn setTraceContextHeader(self: *App, header_name: []const u8) !void {
        const owned = try self.allocator.dupe(u8, header_name);
        errdefer self.allocator.free(owned);

        if (self.trace_context_header) |previous| {
            self.allocator.free(previous);
        }
        self.trace_context_header = owned;
    }

    pub fn includeRouter(
        self: *App,
        prefix: []const u8,
        router: *const router_mod.Router,
        opts: types.IncludeRouterOptions,
    ) !void {
        for (router.httpRoutes()) |route| {
            const combined = try joinPaths(self.allocator, prefix, route.path);
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
            try self.router.addHttpRouteStored(route.method, combined, route.handler, merged_opts);
        }

        for (router.websocketRoutes()) |route| {
            const combined = try joinPaths(self.allocator, prefix, route.path);
            defer self.allocator.free(combined);

            var merged_ws_opts = route.options;
            merged_ws_opts.dependencies = try self.mergeIncludedDependencies(
                route.options.dependencies,
                opts.dependencies,
            );
            try self.router.addWebSocketRouteStored(combined, route.handler, merged_ws_opts);
        }

        self.invalidateGeneratedCaches();
    }

    pub fn mount(self: *App, prefix: []const u8, subapp: *const App) !void {
        try self.includeRouter(prefix, &subapp.router, .{});
    }

    pub fn addMiddleware(self: *App, mw: anytype) !void {
        const T = @TypeOf(mw);

        if (T == Middleware) {
            const name = try self.allocator.dupe(u8, mw.name);
            try self.middleware.append(self.allocator, .{
                .name = name,
                .request_hook = mw.request_hook,
                .response_hook = mw.response_hook,
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
        self.emitAudit(.{
            .category = "lifecycle",
            .action = "startup_complete",
        });

        defer {
            self.emitAudit(.{
                .category = "lifecycle",
                .action = "shutdown_begin",
            });

            var shutdown_failed = false;
            self.runHooks(self.shutdown_hooks.items) catch |err| {
                shutdown_failed = true;
                self.emitAudit(.{
                    .category = "lifecycle",
                    .action = "shutdown_failed",
                    .detail = @errorName(err),
                });
                std.log.err("shutdown hook failed: {s}", .{@errorName(err)});
            };

            if (!shutdown_failed) {
                self.emitAudit(.{
                    .category = "lifecycle",
                    .action = "shutdown_complete",
                });
            }
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

    pub fn openapi(self: *App) ![]const u8 {
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
        return self.dispatchSyntheticWithHeaders(method, target, body, &.{});
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
            else => return err,
        };
        defer req.deinit();
        defer req.runBackgroundTasks() catch |err| {
            std.log.warn("background task failed: {s}", .{@errorName(err)});
        };

        if (raw_request.upgradeRequested() == .websocket) {
            if (try self.router.findWebSocket(req.path, &req)) |ws_route| {
                try self.ensureRequestId(&req);
                self.ensureTraceContext(&req);
                defer req.runDependencyCleanups(self.allocator) catch |err| {
                    std.log.err("dependency cleanup failed: {s}", .{@errorName(err)});
                };

                self.dependency_registry.runRouteDependencies(
                    &req,
                    ws_route.options.dependencies,
                    self.allocator,
                ) catch |err| {
                    switch (err) {
                        error.Unauthorized => self.emitAuthAudit(&req, "websocket_unauthorized", "dependency"),
                        error.InsufficientScope => self.emitAuthAudit(&req, "websocket_insufficient_scope", "dependency"),
                        else => {},
                    }
                    var dep_response = switch (err) {
                        error.Unauthorized => self.unauthorizedResponseForWebSocket(ws_route.options),
                        error.InsufficientScope => self.insufficientScopeResponseForWebSocket(ws_route.options),
                        else => dependencyErrorToResponse(self.allocator, err),
                    };
                    defer dep_response.deinit(self.allocator);
                    try sendResponse(raw_request, self.allocator, &dep_response);
                    return;
                };

                if (!isWebSocketOriginAllowed(req.header("origin"), ws_route.options.allowed_origins)) {
                    self.emitAudit(.{
                        .category = "websocket",
                        .action = "origin_rejected",
                        .request_id = req.requestId() orelse "",
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

                const selected_subprotocol = selectWebSocketSubprotocol(
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
                ws_route.handler(&conn, self.allocator) catch |err| {
                    std.log.warn("websocket handler failed: {s}", .{@errorName(err)});
                };
                return;
            }
        }

        var response = try self.dispatchWithPipeline(&req);
        defer response.deinit(self.allocator);

        try sendResponse(raw_request, self.allocator, &response);
    }

    fn queryLengthFromTarget(target: []const u8) usize {
        const qmark_idx = std.mem.indexOfScalar(u8, target, '?') orelse return 0;
        const rest = target[qmark_idx + 1 ..];
        const fragment_idx = std.mem.indexOfScalar(u8, rest, '#') orelse return rest.len;
        return rest[0..fragment_idx].len;
    }

    const RouteGuardrails = struct {
        max_query_bytes: ?usize = null,
        max_body_bytes: ?usize = null,
    };

    fn resolveHttpRouteGuardrails(self: *App, method: std.http.Method, target: []const u8) RouteGuardrails {
        var probe = Request.initSynthetic(self.allocator, method, target, "") catch return .{};
        defer probe.deinit();

        const route = self.router.findHttp(&probe) catch return .{};
        if (route) |matched| {
            return .{
                .max_query_bytes = matched.options.max_query_bytes,
                .max_body_bytes = matched.options.max_body_bytes,
            };
        }
        return .{};
    }

    fn dispatchWithPipeline(self: *App, req: *Request) !Response {
        try self.ensureRequestId(req);
        self.ensureTraceContext(req);
        const start_ns = std.time.nanoTimestamp();

        self.runRequestMiddleware(req) catch |err| {
            var response = middlewareErrorToResponse(self.allocator, err);
            self.finalizeResponse(req, &response, start_ns);
            return response;
        };

        var response = self.dispatchCore(req) catch |err| {
            std.log.warn("dispatch failed: {s}", .{@errorName(err)});
            var fallback = Response.text("internal server error").withStatus(.internal_server_error);
            self.finalizeResponse(req, &fallback, start_ns);
            return fallback;
        };
        errdefer response.deinit(self.allocator);

        self.runResponseMiddleware(req, &response) catch |err| {
            response.deinit(self.allocator);
            var fallback = middlewareErrorToResponse(self.allocator, err);
            self.finalizeResponse(req, &fallback, start_ns);
            return fallback;
        };

        self.finalizeResponse(req, &response, start_ns);
        return response;
    }

    fn dispatchCore(self: *App, req: *Request) !Response {
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
                const html = try self.docsHtml();
                return .{
                    .status = .ok,
                    .body = html,
                    .content_type = "text/html; charset=utf-8",
                };
            }
        }

        if (self.cfg.redoc_url) |redoc_url| {
            if (std.mem.eql(u8, req.path, redoc_url)) {
                const html = try self.redocHtml();
                return .{
                    .status = .ok,
                    .body = html,
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

        if (try self.router.findHttp(req)) |route| {
            self.seedRouteValidationMode(req, route.options);
            defer req.runDependencyCleanups(self.allocator) catch |err| {
                std.log.err("dependency cleanup failed: {s}", .{@errorName(err)});
            };

            const runtime_deps = try self.buildRuntimeDependencies(
                route.options.dependencies,
                route.options.injected_dependencies,
            );
            defer self.allocator.free(runtime_deps);

            self.dependency_registry.runRouteDependencies(req, runtime_deps, self.allocator) catch |err| {
                if (err == error.Unauthorized) {
                    self.emitAuthAudit(req, "http_unauthorized", "dependency");
                    return self.unauthorizedResponseForRoute(route.options);
                }
                if (err == error.InsufficientScope) {
                    self.emitAuthAudit(req, "http_insufficient_scope", "dependency");
                    return self.insufficientScopeResponseForRoute(route.options);
                }
                return dependencyErrorToResponse(self.allocator, err);
            };

            var route_response = route.handler(req, self.allocator) catch |err| {
                if (err == error.ValidationFailed and req.hasValidationIssues()) {
                    return validationIssuesToResponse(self.allocator, req.validationIssues());
                }
                if (err == error.UnsupportedMediaType) {
                    return Response.text("unsupported media type").withStatus(.unsupported_media_type);
                }
                if (err == error.Unauthorized) {
                    self.emitAuthAudit(req, "http_unauthorized", "handler");
                    return self.unauthorizedResponseForRoute(route.options);
                }
                if (err == error.InsufficientScope) {
                    self.emitAuthAudit(req, "http_insufficient_scope", "handler");
                    return self.insufficientScopeResponseForRoute(route.options);
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

        return Response.text("not found").withStatus(.not_found);
    }

    fn seedRouteValidationMode(self: *const App, req: *Request, route_options: types.StoredRouteOptions) void {
        const strict_enabled = route_options.strict_validation orelse self.cfg.strict_validation;
        req.setDependencyValue("zigmund.validation.strict", if (strict_enabled) "true" else "false") catch |err| {
            std.log.warn("failed to set validation strict mode dependency: {s}", .{@errorName(err)});
        };
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
    ) ![]types.DependencySpec {
        var count: usize = route_dependencies.len;
        for (injected_dependencies) |dep| {
            if (self.dependency_registry.lookup(dep.name) != null) count += 1;
        }

        if (count == 0) return try self.allocator.alloc(types.DependencySpec, 0);

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

        return merged;
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

    fn runHooks(self: *App, hooks: []const LifecycleHook) !void {
        _ = self;
        for (hooks) |hook| try hook.run();
    }

    fn runRequestMiddleware(self: *App, req: *Request) !void {
        for (self.middleware.items) |entry| {
            if (entry.request_hook) |hook| {
                try hook(req, self.allocator);
            }
        }
    }

    fn runResponseMiddleware(self: *App, req: *Request, response: *Response) !void {
        for (self.middleware.items) |entry| {
            if (entry.response_hook) |hook| {
                try hook(req, response, self.allocator);
            }
        }
    }

    fn ensureRequestId(self: *App, req: *Request) !void {
        if (req.requestId() == null) {
            if (req.header("x-request-id")) |incoming| {
                if (incoming.len != 0) {
                    try req.setRequestId(incoming);
                }
            }
        }

        if (req.requestId() == null) {
            const next_id = self.request_id_counter.fetchAdd(1, .monotonic) + 1;
            var generated_buf: [64]u8 = undefined;
            const generated = try std.fmt.bufPrint(
                &generated_buf,
                "req-{d}-{d}",
                .{ next_id, std.time.milliTimestamp() },
            );
            try req.setRequestId(generated);
        }

        if (req.requestId()) |request_id| {
            req.setDependencyValue("request_id", request_id) catch |err| {
                std.log.warn("failed to set request_id dependency: {s}", .{@errorName(err)});
            };
        }
    }

    fn ensureTraceContext(self: *App, req: *Request) void {
        const header_name = self.trace_context_header orelse "traceparent";
        const trace_context = req.header(header_name) orelse req.header("x-correlation-id") orelse return;
        if (trace_context.len == 0) return;

        req.setDependencyValue("trace_context", trace_context) catch |err| {
            std.log.warn("failed to set trace_context dependency: {s}", .{@errorName(err)});
        };

        if (parseTraceparent(trace_context)) |parsed| {
            req.setDependencyValue("trace_id", parsed.trace_id) catch |err| {
                std.log.warn("failed to set trace_id dependency: {s}", .{@errorName(err)});
            };
            req.setDependencyValue("span_id", parsed.span_id) catch |err| {
                std.log.warn("failed to set span_id dependency: {s}", .{@errorName(err)});
            };
            req.setDependencyValue("trace_flags", parsed.trace_flags) catch |err| {
                std.log.warn("failed to set trace_flags dependency: {s}", .{@errorName(err)});
            };
        }
    }

    const TraceIdentity = struct {
        trace_context: []const u8,
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
        self.attachRequestIdHeader(req, response);
        const latency_us = elapsedMicros(start_ns);
        self.emitTelemetry(req, response.status, latency_us);
        self.emitTrace(req, response.status, latency_us);
        self.emitAccessLog(req, response.status, latency_us);
        self.emitMetrics(req, response.status, latency_us);
    }

    fn attachRequestIdHeader(self: *App, req: *Request, response: *Response) void {
        if (response.hasHeader("x-request-id")) return;
        const request_id = req.requestId() orelse return;
        response.setHeader(self.allocator, "x-request-id", request_id) catch |err| {
            std.log.warn("failed to set x-request-id header: {s}", .{@errorName(err)});
        };
    }

    fn emitTelemetry(self: *App, req: *const Request, status: std.http.Status, latency_us: u64) void {
        const trace_identity = buildTraceIdentity(req);
        const event: TelemetryEvent = .{
            .request_id = req.requestId() orelse "",
            .trace_id = trace_identity.trace_id,
            .span_id = trace_identity.span_id,
            .method = req.method,
            .path = req.path,
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
            jsonTelemetrySink(event, self.allocator) catch |err| {
                std.log.warn("telemetry json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn emitTrace(self: *App, req: *const Request, status: std.http.Status, latency_us: u64) void {
        const trace_identity = buildTraceIdentity(req);
        const event: TraceEvent = .{
            .request_id = req.requestId() orelse "",
            .trace_context = trace_identity.trace_context,
            .trace_id = trace_identity.trace_id,
            .span_id = trace_identity.span_id,
            .method = req.method,
            .path = req.path,
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
            jsonTraceSink(event, self.allocator) catch |err| {
                std.log.warn("trace json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn emitAccessLog(self: *App, req: *const Request, status: std.http.Status, latency_us: u64) void {
        var addr_buf: [128]u8 = undefined;
        const remote_addr = if (req.peerAddress()) |peer|
            std.fmt.bufPrint(&addr_buf, "{f}", .{peer}) catch ""
        else
            "";
        const trace_identity = buildTraceIdentity(req);

        const event: AccessLogEvent = .{
            .request_id = req.requestId() orelse "",
            .trace_context = trace_identity.trace_context,
            .trace_id = trace_identity.trace_id,
            .span_id = trace_identity.span_id,
            .method = req.method,
            .path = req.path,
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
            jsonAccessLogSink(event, self.allocator) catch |err| {
                std.log.warn("access log json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn emitMetrics(self: *App, req: *const Request, status: std.http.Status, latency_us: u64) void {
        self.metrics.observe(req.method, req.path, status, latency_us) catch |err| {
            std.log.warn("metrics registry observe failed: {s}", .{@errorName(err)});
        };

        const count_event: MetricsEvent = .{
            .name = "zigmund_http_requests_total",
            .value = 1,
            .method = req.method,
            .path = req.path,
            .status = status,
            .latency_us = latency_us,
        };

        const latency_event: MetricsEvent = .{
            .name = "zigmund_http_request_latency_us",
            .value = @as(f64, @floatFromInt(latency_us)),
            .method = req.method,
            .path = req.path,
            .status = status,
            .latency_us = latency_us,
        };

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
            jsonMetricsSink(count_event, self.allocator) catch |err| {
                std.log.warn("metrics json sink failed: {s}", .{@errorName(err)});
            };
            jsonMetricsSink(latency_event, self.allocator) catch |err| {
                std.log.warn("metrics json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn emitAudit(self: *App, event: AuditEvent) void {
        if (self.audit_sink) |sink| {
            sink(event, self.allocator) catch |err| {
                std.log.warn("audit sink failed: {s}", .{@errorName(err)});
            };
            return;
        }

        if (self.cfg.structured_audit_logs) {
            jsonAuditSink(event, self.allocator) catch |err| {
                std.log.warn("audit json sink failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn emitStartupConfigAudit(self: *App, cfg: runtime.ServerConfig) void {
        const detail = std.fmt.allocPrint(
            self.allocator,
            "{{\"host\":{f},\"port\":{d},\"workers\":{d},\"recv_buffer_size\":{d},\"send_buffer_size\":{d},\"max_header_bytes\":{d},\"max_body_bytes\":{d},\"max_connections\":{d},\"accept_poll_interval_ms\":{d},\"header_timeout_ms\":{d},\"idle_timeout_ms\":{d},\"shutdown_grace_period_ms\":{d},\"trusted_proxy_headers\":{},\"trusted_proxy_cidrs\":{d},\"tls_enabled\":{}}}",
            .{
                std.json.fmt(cfg.host, .{}),
                cfg.port,
                cfg.resolvedWorkerCount(),
                cfg.recv_buffer_size,
                cfg.send_buffer_size,
                cfg.max_header_bytes,
                cfg.max_body_bytes,
                cfg.max_connections,
                cfg.accept_poll_interval_ms,
                cfg.header_timeout_ms,
                cfg.idle_timeout_ms,
                cfg.shutdown_grace_period_ms,
                cfg.trusted_proxy_headers,
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
        if (!needsResponseShaping(route_options)) return;
        if (!isJsonContentType(response.content_type)) return;

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response.body, .{}) catch return;
        defer parsed.deinit();

        var shaped = parsed.value;
        try applyResponseModelFieldFilter(
            self.allocator,
            &shaped,
            route_options.response_model_field_rules,
        );

        try applyTopLevelIncludeExclude(
            self.allocator,
            &shaped,
            route_options.response_model_include,
            route_options.response_model_exclude,
        );

        if (route_options.response_model_exclude_defaults) {
            try applyExcludeDefaults(
                &shaped,
                route_options.response_model_field_rules,
            );
        }

        if (route_options.response_model_exclude_none) {
            try pruneNullValues(self.allocator, &shaped);
        }

        if (route_options.response_model_by_alias) {
            try applyResponseModelAliases(
                self.allocator,
                &shaped,
                route_options.response_model_field_rules,
            );
        }

        const payload = try std.fmt.allocPrint(self.allocator, "{f}", .{std.json.fmt(shaped, .{})});
        if (response.owned_body) |body| self.allocator.free(body);
        response.body = payload;
        response.owned_body = payload;
    }

    fn unauthorizedResponseForRoute(self: *const App, route_options: types.StoredRouteOptions) Response {
        var challenge: []const u8 = "Bearer";
        if (self.routeSecurityChallenge(route_options)) |route_challenge| {
            challenge = route_challenge;
        }

        var response = Response.text("unauthorized").withStatus(.unauthorized);
        response.setHeader(self.allocator, "www-authenticate", challenge) catch {};
        return response;
    }

    fn unauthorizedResponseForWebSocket(self: *const App, route_options: types.WebSocketRouteOptions) Response {
        const challenge = self.dependenciesSecurityChallenge(route_options.dependencies) orelse "Bearer";
        var response = Response.text("unauthorized").withStatus(.unauthorized);
        response.setHeader(self.allocator, "www-authenticate", challenge) catch {};
        return response;
    }

    fn insufficientScopeResponseForRoute(self: *const App, route_options: types.StoredRouteOptions) Response {
        const challenge_base = self.routeSecurityChallenge(route_options) orelse "Bearer";
        const required_scopes = self.routeRequiredScopes(route_options);

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
                ) catch {};
                return response;
            };

            if (required_scopes.len > 0) {
                writer.writeAll(", scope=\"") catch {};
                for (required_scopes, 0..) |scope, idx| {
                    if (idx != 0) writer.writeByte(' ') catch {};
                    writer.writeAll(scope) catch {};
                }
                writer.writeByte('"') catch {};
            }

            const challenge = challenge_buf.toOwnedSlice(self.allocator) catch {
                response.setHeader(
                    self.allocator,
                    "www-authenticate",
                    "Bearer error=\"insufficient_scope\"",
                ) catch {};
                return response;
            };
            defer self.allocator.free(challenge);
            response.setHeader(self.allocator, "www-authenticate", challenge) catch {};
            return response;
        }

        response.setHeader(self.allocator, "www-authenticate", challenge_base) catch {};
        return response;
    }

    fn insufficientScopeResponseForWebSocket(
        self: *const App,
        route_options: types.WebSocketRouteOptions,
    ) Response {
        const challenge_base = self.dependenciesSecurityChallenge(route_options.dependencies) orelse "Bearer";
        const required_scopes = self.dependenciesRequiredScopes(route_options.dependencies) orelse &.{};

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
                ) catch {};
                return response;
            };

            if (required_scopes.len > 0) {
                writer.writeAll(", scope=\"") catch {};
                for (required_scopes, 0..) |scope, idx| {
                    if (idx != 0) writer.writeByte(' ') catch {};
                    writer.writeAll(scope) catch {};
                }
                writer.writeByte('"') catch {};
            }

            const challenge = challenge_buf.toOwnedSlice(self.allocator) catch {
                response.setHeader(
                    self.allocator,
                    "www-authenticate",
                    "Bearer error=\"insufficient_scope\"",
                ) catch {};
                return response;
            };
            defer self.allocator.free(challenge);
            response.setHeader(self.allocator, "www-authenticate", challenge) catch {};
            return response;
        }

        response.setHeader(self.allocator, "www-authenticate", challenge_base) catch {};
        return response;
    }

    fn routeSecurityChallenge(self: *const App, route_options: types.StoredRouteOptions) ?[]const u8 {
        if (self.dependenciesSecurityChallenge(route_options.dependencies)) |challenge| return challenge;
        if (self.dependenciesSecurityChallenge(route_options.injected_dependencies)) |challenge| return challenge;
        return null;
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
            if (challengeForSecurityScheme(scheme.scheme)) |challenge| return challenge;
        }
        return null;
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

    fn normalizeTelemetrySink(sink: anytype) TelemetryFn {
        const T = @TypeOf(sink);
        if (T == TelemetryFn) return sink;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isTelemetrySinkType(T)) {
                const ptr: TelemetryFn = &sink;
                return ptr;
            }
        }
        @compileError("Telemetry sink must be fn(App.TelemetryEvent, std.mem.Allocator) !void");
    }

    fn normalizeTraceSink(sink: anytype) TraceFn {
        const T = @TypeOf(sink);
        if (T == TraceFn) return sink;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isTraceSinkType(T)) {
                const ptr: TraceFn = &sink;
                return ptr;
            }
        }
        @compileError("Trace sink must be fn(App.TraceEvent, std.mem.Allocator) !void");
    }

    fn normalizeAccessLogSink(sink: anytype) AccessLogFn {
        const T = @TypeOf(sink);
        if (T == AccessLogFn) return sink;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isAccessLogSinkType(T)) {
                const ptr: AccessLogFn = &sink;
                return ptr;
            }
        }
        @compileError("Access log sink must be fn(App.AccessLogEvent, std.mem.Allocator) !void");
    }

    fn normalizeMetricsSink(sink: anytype) MetricsFn {
        const T = @TypeOf(sink);
        if (T == MetricsFn) return sink;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isMetricsSinkType(T)) {
                const ptr: MetricsFn = &sink;
                return ptr;
            }
        }
        @compileError("Metrics sink must be fn(App.MetricsEvent, std.mem.Allocator) !void");
    }

    fn normalizeAuditSink(sink: anytype) AuditFn {
        const T = @TypeOf(sink);
        if (T == AuditFn) return sink;
        if (@typeInfo(T) == .@"fn") {
            if (comptime isAuditSinkType(T)) {
                const ptr: AuditFn = &sink;
                return ptr;
            }
        }
        @compileError("Audit sink must be fn(App.AuditEvent, std.mem.Allocator) !void");
    }

    fn isTelemetrySinkType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != TelemetryEvent) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        return isVoidOrErrorVoid(info.return_type orelse return false);
    }

    fn isTraceSinkType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != TraceEvent) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        return isVoidOrErrorVoid(info.return_type orelse return false);
    }

    fn isAccessLogSinkType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != AccessLogEvent) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        return isVoidOrErrorVoid(info.return_type orelse return false);
    }

    fn isMetricsSinkType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != MetricsEvent) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        return isVoidOrErrorVoid(info.return_type orelse return false);
    }

    fn isAuditSinkType(comptime T: type) bool {
        if (@typeInfo(T) != .@"fn") return false;
        const info = @typeInfo(T).@"fn";
        if (info.params.len != 2) return false;
        if (info.params[0].type != AuditEvent) return false;
        if (info.params[1].type != std.mem.Allocator) return false;
        return isVoidOrErrorVoid(info.return_type orelse return false);
    }

    fn docsHtml(self: *App) ![]const u8 {
        if (self.docs_cache) |html| return html;

        const openapi_url = self.cfg.openapi_url orelse "/openapi.json";
        const html = try docs_ui.renderSwagger(
            self.allocator,
            self.cfg.title,
            openapi_url,
            self.cfg.docs,
        );
        self.docs_cache = html;
        return html;
    }

    fn redocHtml(self: *App) ![]const u8 {
        if (self.redoc_cache) |html| return html;

        const openapi_url = self.cfg.openapi_url orelse "/openapi.json";
        const html = try docs_ui.renderRedoc(
            self.allocator,
            self.cfg.title,
            openapi_url,
            self.cfg.redoc,
        );
        self.redoc_cache = html;
        return html;
    }

    fn invalidateGeneratedCaches(self: *App) void {
        self.freeGeneratedCaches();
    }

    fn freeGeneratedCaches(self: *App) void {
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

fn needsResponseShaping(options: types.StoredRouteOptions) bool {
    if (options.response_model_field_rules.len != 0) return true;
    if (options.response_model_include.len != 0) return true;
    if (options.response_model_exclude.len != 0) return true;
    if (options.response_model_exclude_none) return true;
    if (options.response_model_exclude_unset) return true;
    if (options.response_model_exclude_defaults) return true;
    return false;
}

fn elapsedMicros(start_ns: i128) u64 {
    const now_ns = std.time.nanoTimestamp();
    const latency_ns: i128 = if (now_ns > start_ns) now_ns - start_ns else 0;
    return @intCast(@divFloor(latency_ns, 1_000));
}

fn isJsonContentType(content_type: []const u8) bool {
    const media_type = std.mem.trim(u8, mediaTypeToken(content_type), " \t");
    if (std.ascii.eqlIgnoreCase(media_type, "application/json")) return true;
    return std.mem.endsWith(u8, media_type, "+json");
}

fn mediaTypeToken(raw: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
    return raw[0..end];
}

fn applyTopLevelIncludeExclude(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    include: []const []const u8,
    exclude: []const []const u8,
) !void {
    if (include.len == 0 and exclude.len == 0) return;

    var path_buf: std.ArrayList(u8) = .empty;
    defer path_buf.deinit(allocator);

    try applyIncludeExcludeRecursive(allocator, value, include, exclude, &path_buf);
}

fn applyResponseModelFieldFilter(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    rules: []const types.ResponseModelFieldRule,
) !void {
    if (rules.len == 0) return;

    const include_paths = try allocator.alloc([]const u8, rules.len);
    defer allocator.free(include_paths);

    for (rules, 0..) |rule, idx| {
        include_paths[idx] = rule.path;
    }
    try applyTopLevelIncludeExclude(allocator, value, include_paths, &.{});
}

fn applyExcludeDefaults(
    value: *std.json.Value,
    rules: []const types.ResponseModelFieldRule,
) !void {
    for (rules) |rule| {
        if (rule.default_value == .none) continue;
        try removePathIfDefault(value, rule.path, rule.default_value);
    }
}

fn removePathIfDefault(
    value: *std.json.Value,
    path: []const u8,
    default_value: types.ResponseModelDefaultValue,
) !void {
    if (path.len == 0) return;

    switch (value.*) {
        .object => |*object| {
            const split = splitPath(path);
            if (split.tail.len == 0) {
                const current = object.get(split.head) orelse return;
                if (jsonValueMatchesDefault(current, default_value)) {
                    _ = object.swapRemove(split.head);
                }
                return;
            }

            if (object.getPtr(split.head)) |child| {
                try removePathIfDefault(child, split.tail, default_value);
            }
        },
        .array => |*array| {
            for (array.items) |*item| {
                try removePathIfDefault(item, path, default_value);
            }
        },
        else => {},
    }
}

fn jsonValueMatchesDefault(value: std.json.Value, default_value: types.ResponseModelDefaultValue) bool {
    return switch (default_value) {
        .none => false,
        .null => value == .null,
        .bool => |expected| switch (value) {
            .bool => |actual| actual == expected,
            else => false,
        },
        .integer => |expected| switch (value) {
            .integer => |actual| actual == expected,
            .float => |actual| actual == @as(f64, @floatFromInt(expected)),
            .number_string => |actual| blk: {
                const parsed = std.fmt.parseInt(i64, actual, 10) catch break :blk false;
                break :blk parsed == expected;
            },
            else => false,
        },
        .float => |expected| switch (value) {
            .float => |actual| actual == expected,
            .integer => |actual| @as(f64, @floatFromInt(actual)) == expected,
            .number_string => |actual| blk: {
                const parsed = std.fmt.parseFloat(f64, actual) catch break :blk false;
                break :blk parsed == expected;
            },
            else => false,
        },
        .string => |expected| switch (value) {
            .string => |actual| std.mem.eql(u8, actual, expected),
            else => false,
        },
    };
}

fn applyResponseModelAliases(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    rules: []const types.ResponseModelFieldRule,
) !void {
    var max_depth: usize = 0;
    for (rules) |rule| {
        if (rule.alias == null) continue;
        max_depth = @max(max_depth, pathDepth(rule.path));
    }
    if (max_depth == 0) return;

    var depth = max_depth;
    while (depth > 0) : (depth -= 1) {
        for (rules) |rule| {
            const alias = rule.alias orelse continue;
            if (pathDepth(rule.path) != depth) continue;
            try renamePathField(allocator, value, rule.path, alias);
        }
    }
}

fn renamePathField(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    path: []const u8,
    alias: []const u8,
) !void {
    if (path.len == 0) return;

    switch (value.*) {
        .object => |*object| {
            const split = splitPath(path);
            if (split.tail.len == 0) {
                if (std.mem.eql(u8, split.head, alias)) return;

                const removed = object.fetchSwapRemove(split.head) orelse return;
                if (object.get(alias) == null) {
                    try object.put(alias, removed.value);
                }
                return;
            }

            if (object.getPtr(split.head)) |child| {
                try renamePathField(allocator, child, split.tail, alias);
            }
        },
        .array => |*array| {
            for (array.items) |*item| {
                try renamePathField(allocator, item, path, alias);
            }
        },
        else => {},
    }
}

fn splitPath(path: []const u8) struct { head: []const u8, tail: []const u8 } {
    const dot = std.mem.indexOfScalar(u8, path, '.') orelse {
        return .{ .head = path, .tail = "" };
    };
    return .{
        .head = path[0..dot],
        .tail = path[dot + 1 ..],
    };
}

fn pathDepth(path: []const u8) usize {
    if (path.len == 0) return 0;

    var depth: usize = 1;
    for (path) |ch| {
        if (ch == '.') depth += 1;
    }
    return depth;
}

fn applyIncludeExcludeRecursive(
    allocator: std.mem.Allocator,
    value: *std.json.Value,
    include: []const []const u8,
    exclude: []const []const u8,
    path_buf: *std.ArrayList(u8),
) !void {
    switch (value.*) {
        .object => |*object| {
            var remove_keys: std.ArrayList([]const u8) = .empty;
            defer remove_keys.deinit(allocator);

            var iter = object.iterator();
            while (iter.next()) |entry| {
                const restore_len = path_buf.items.len;
                if (restore_len != 0) try path_buf.append(allocator, '.');
                try path_buf.appendSlice(allocator, entry.key_ptr.*);
                const path = path_buf.items;

                const include_exact = pathInList(include, path);
                const include_child = pathHasChild(include, path);
                const include_match = include.len == 0 or include_exact or include_child;
                const exclude_exact = pathInList(exclude, path);
                const exclude_child = pathHasChild(exclude, path);

                if (!include_match or exclude_exact) {
                    try remove_keys.append(allocator, entry.key_ptr.*);
                    path_buf.items.len = restore_len;
                    continue;
                }

                if (include_child or exclude_child) {
                    try applyIncludeExcludeRecursive(allocator, entry.value_ptr, include, exclude, path_buf);
                }

                path_buf.items.len = restore_len;
            }

            for (remove_keys.items) |key| {
                _ = object.swapRemove(key);
            }
        },
        .array => |*array| {
            for (array.items) |*item| {
                try applyIncludeExcludeRecursive(allocator, item, include, exclude, path_buf);
            }
        },
        else => {},
    }
}

fn pruneNullValues(allocator: std.mem.Allocator, value: *std.json.Value) !void {
    switch (value.*) {
        .object => |*object| {
            var remove_keys: std.ArrayList([]const u8) = .empty;
            defer remove_keys.deinit(allocator);

            var iter = object.iterator();
            while (iter.next()) |entry| {
                try pruneNullValues(allocator, entry.value_ptr);
                if (entry.value_ptr.* == .null) {
                    try remove_keys.append(allocator, entry.key_ptr.*);
                }
            }

            for (remove_keys.items) |key| {
                _ = object.swapRemove(key);
            }
        },
        .array => |*array| {
            var idx: usize = 0;
            while (idx < array.items.len) : (idx += 1) {
                try pruneNullValues(allocator, &array.items[idx]);
            }

            var write_idx: usize = 0;
            for (array.items) |item| {
                if (item == .null) continue;
                array.items[write_idx] = item;
                write_idx += 1;
            }
            array.items.len = write_idx;
        },
        else => {},
    }
}

fn pathInList(list: []const []const u8, needle: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

fn pathHasChild(list: []const []const u8, path: []const u8) bool {
    if (path.len == 0) return list.len != 0;

    for (list) |item| {
        if (item.len <= path.len) continue;
        if (!std.mem.startsWith(u8, item, path)) continue;
        if (item[path.len] == '.') return true;
    }
    return false;
}

fn isWebSocketOriginAllowed(origin_header: ?[]const u8, allowed_origins: []const []const u8) bool {
    if (allowed_origins.len == 0) return true;

    const origin = std.mem.trim(u8, origin_header orelse return false, " \t");
    if (origin.len == 0) return false;

    for (allowed_origins) |item| {
        const allowed = std.mem.trim(u8, item, " \t");
        if (allowed.len == 0) continue;
        if (std.mem.eql(u8, allowed, "*")) return true;
        if (std.ascii.eqlIgnoreCase(allowed, origin)) return true;
    }

    return false;
}

fn selectWebSocketSubprotocol(
    offered_header: ?[]const u8,
    supported_subprotocols: []const []const u8,
) ?[]const u8 {
    if (supported_subprotocols.len == 0) return null;
    const offered = offered_header orelse return null;

    var offered_tokens = std.mem.splitScalar(u8, offered, ',');
    while (offered_tokens.next()) |token_raw| {
        const token = std.mem.trim(u8, token_raw, " \t");
        if (token.len == 0) continue;

        for (supported_subprotocols) |supported_raw| {
            const supported = std.mem.trim(u8, supported_raw, " \t");
            if (supported.len == 0) continue;
            if (std.mem.eql(u8, token, supported)) return supported;
        }
    }

    return null;
}

fn sendResponse(raw: *std.http.Server.Request, allocator: std.mem.Allocator, response: *const Response) !void {
    var headers: std.ArrayList(std.http.Header) = .empty;
    defer headers.deinit(allocator);

    try headers.append(allocator, .{
        .name = "content-type",
        .value = response.content_type,
    });

    try headers.appendSlice(allocator, response.headers.items);

    try raw.respond(response.body, .{
        .status = response.status,
        .extra_headers = headers.items,
    });
}

fn joinPaths(allocator: std.mem.Allocator, prefix: []const u8, path: []const u8) ![]u8 {
    const normalized_prefix = if (prefix.len == 0) "/" else prefix;
    if (normalized_prefix[0] != '/' or path.len == 0 or path[0] != '/') return error.InvalidPath;

    if (std.mem.eql(u8, normalized_prefix, "/")) {
        return allocator.dupe(u8, path);
    }

    const prefix_no_trailing = std.mem.trimRight(u8, normalized_prefix, "/");
    if (std.mem.eql(u8, path, "/")) {
        return std.fmt.allocPrint(allocator, "{s}", .{prefix_no_trailing});
    }
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix_no_trailing, path });
}

fn dependencyErrorToResponse(allocator: std.mem.Allocator, err: deps.RunError) Response {
    return switch (err) {
        error.Unauthorized => unauthorizedResponse(allocator),
        error.InsufficientScope => insufficientScopeResponse(allocator),
        error.MissingDependency => Response.text("missing dependency").withStatus(.internal_server_error),
        error.DependencyCycleDetected => Response.text("dependency cycle detected").withStatus(.internal_server_error),
        error.DependencyExecutionFailed => Response.text("dependency execution failed").withStatus(.internal_server_error),
    };
}

fn middlewareErrorToResponse(allocator: std.mem.Allocator, err: anyerror) Response {
    if (std.mem.eql(u8, @errorName(err), "Unauthorized")) {
        return unauthorizedResponse(allocator);
    }
    if (std.mem.eql(u8, @errorName(err), "InsufficientScope")) {
        return insufficientScopeResponse(allocator);
    }
    return Response.text("middleware execution failed").withStatus(.internal_server_error);
}

fn unauthorizedResponse(allocator: std.mem.Allocator) Response {
    var response = Response.text("unauthorized").withStatus(.unauthorized);
    response.setHeader(allocator, "www-authenticate", "Bearer") catch {};
    return response;
}

fn insufficientScopeResponse(allocator: std.mem.Allocator) Response {
    var response = Response.text("forbidden").withStatus(.forbidden);
    response.setHeader(allocator, "www-authenticate", "Bearer error=\"insufficient_scope\"") catch {};
    return response;
}

fn challengeForSecurityScheme(scheme: security.OpenApiSecurityScheme) ?[]const u8 {
    return switch (scheme) {
        .http => |http| httpChallenge(http.scheme),
        .oauth2, .openid_connect => "Bearer",
        .api_key => null,
    };
}

fn httpChallenge(raw_scheme: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(raw_scheme, "basic")) {
        return "Basic realm=\"zigmund\"";
    }
    if (std.ascii.eqlIgnoreCase(raw_scheme, "bearer")) return "Bearer";
    if (std.ascii.eqlIgnoreCase(raw_scheme, "digest")) {
        return "Digest realm=\"zigmund\", qop=\"auth\", algorithm=SHA-256";
    }
    return raw_scheme;
}

fn validationIssuesToResponse(
    allocator: std.mem.Allocator,
    issues: []const Request.ValidationIssue,
) !Response {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var writer = out.writer(allocator);
    try writer.writeAll("{\"detail\":[");

    for (issues, 0..) |issue, idx| {
        if (idx != 0) try writer.writeAll(",");

        try writer.writeAll("{\"loc\":[");
        try writeJsonString(&writer, issue.location.asString());
        try writer.writeAll(",");
        try writeJsonString(&writer, issue.field);
        try writer.writeAll("],");

        try writer.writeAll("\"msg\":");
        try writeJsonString(&writer, issue.message);
        try writer.writeAll(",");

        try writer.writeAll("\"type\":");
        try writeJsonString(&writer, issue.issue_type);

        if (issue.input) |input| {
            try writer.writeAll(",\"input\":");
            try writeJsonString(&writer, input);
        }

        try writer.writeAll("}");
    }

    try writer.writeAll("]}");

    const payload = try out.toOwnedSlice(allocator);
    return .{
        .status = .unprocessable_entity,
        .body = payload,
        .content_type = "application/json",
        .owned_body = payload,
    };
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.print("{f}", .{std.json.fmt(value, .{})});
}

fn jsonTelemetrySink(event: App.TelemetryEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"telemetry\",\"request_id\":{f},\"trace_id\":{f},\"span_id\":{f},\"method\":{f},\"path\":{f},\"status\":{d},\"latency_us\":{d}}}",
        .{
            std.json.fmt(event.request_id, .{}),
            std.json.fmt(event.trace_id, .{}),
            std.json.fmt(event.span_id, .{}),
            std.json.fmt(@tagName(event.method), .{}),
            std.json.fmt(event.path, .{}),
            @intFromEnum(event.status),
            event.latency_us,
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

fn jsonTraceSink(event: App.TraceEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"trace\",\"request_id\":{f},\"trace_context\":{f},\"trace_id\":{f},\"span_id\":{f},\"method\":{f},\"path\":{f},\"status\":{d},\"latency_us\":{d}}}",
        .{
            std.json.fmt(event.request_id, .{}),
            std.json.fmt(event.trace_context, .{}),
            std.json.fmt(event.trace_id, .{}),
            std.json.fmt(event.span_id, .{}),
            std.json.fmt(@tagName(event.method), .{}),
            std.json.fmt(event.path, .{}),
            @intFromEnum(event.status),
            event.latency_us,
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

fn jsonAccessLogSink(event: App.AccessLogEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"access_log\",\"request_id\":{f},\"trace_context\":{f},\"trace_id\":{f},\"span_id\":{f},\"method\":{f},\"path\":{f},\"status\":{d},\"latency_us\":{d},\"remote_addr\":{f},\"user_agent\":{f}}}",
        .{
            std.json.fmt(event.request_id, .{}),
            std.json.fmt(event.trace_context, .{}),
            std.json.fmt(event.trace_id, .{}),
            std.json.fmt(event.span_id, .{}),
            std.json.fmt(@tagName(event.method), .{}),
            std.json.fmt(event.path, .{}),
            @intFromEnum(event.status),
            event.latency_us,
            std.json.fmt(event.remote_addr, .{}),
            std.json.fmt(event.user_agent, .{}),
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

fn jsonMetricsSink(event: App.MetricsEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"metrics\",\"name\":{f},\"value\":{d},\"method\":{f},\"path\":{f},\"status\":{d},\"latency_us\":{d}}}",
        .{
            std.json.fmt(event.name, .{}),
            event.value,
            std.json.fmt(@tagName(event.method), .{}),
            std.json.fmt(event.path, .{}),
            @intFromEnum(event.status),
            event.latency_us,
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

fn jsonAuditSink(event: App.AuditEvent, allocator: std.mem.Allocator) !void {
    const line = try std.fmt.allocPrint(
        allocator,
        "{{\"event\":\"audit\",\"category\":{f},\"action\":{f},\"request_id\":{f},\"method\":{f},\"path\":{f},\"detail\":{f}}}",
        .{
            std.json.fmt(event.category, .{}),
            std.json.fmt(event.action, .{}),
            std.json.fmt(event.request_id, .{}),
            std.json.fmt(event.method, .{}),
            std.json.fmt(event.path, .{}),
            std.json.fmt(event.detail, .{}),
        },
    );
    defer allocator.free(line);
    try writeStderrLine(line);
}

fn writeStderrLine(line: []const u8) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    try stderr_writer.interface.writeAll(line);
    try stderr_writer.interface.writeAll("\n");
    try stderr_writer.interface.flush();
}

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
