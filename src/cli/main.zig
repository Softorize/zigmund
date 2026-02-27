const std = @import("std");
const zigmund = @import("zigmund");
const builtin = @import("builtin");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    const command = args.next() orelse "serve";

    if (std.mem.eql(u8, command, "dev")) {
        try runDevMode(allocator, &args);
        return;
    }

    var app = try buildDefaultApp(allocator);
    defer app.deinit();

    if (std.mem.eql(u8, command, "serve")) {
        var owned_serve_flags: ServeFlagsOwned = .{};
        defer owned_serve_flags.deinit(allocator);

        var cfg = zigmund.ServerConfig{};
        try parseServeFlags(allocator, &args, &cfg, &owned_serve_flags);

        try app.serve(cfg);
        return;
    }

    if (std.mem.eql(u8, command, "routes")) {
        const json_output = try parseRoutesFlags(&args);
        if (json_output) {
            try printRoutesJson(allocator, &app);
        } else {
            try printRoutes(&app);
        }
        return;
    }

    if (std.mem.eql(u8, command, "openapi")) {
        const opts = try parseOpenApiFlags(&args);
        if (opts.deterministic) {
            app.cfg.openapi_deterministic = true;
        }

        const doc = try app.openapi();
        if (opts.diff_path) |path| {
            try assertOpenApiSnapshotFile(allocator, doc, path);
        }
        if (opts.out_path) |path| {
            try writeFile(path, doc);
        } else if (opts.diff_path == null) {
            try writeStdout(doc);
            try writeStdout("\n");
        }
        return;
    }

    if (std.mem.eql(u8, command, "cloud")) {
        const opts = try parseCloudFlags(&args);
        const plan = try renderCloudPlan(allocator, &app, opts.provider);
        defer allocator.free(plan);

        if (opts.out_path) |path| {
            try writeFile(path, plan);
        } else {
            try writeStdout(plan);
            try writeStdout("\n");
        }

        if (opts.emit_dir) |dir| {
            try emitCloudScaffold(allocator, &app, opts.provider, dir);
        }
        return;
    }

    if (std.mem.eql(u8, command, "sbom")) {
        const out_path = try parseOutputFlags(&args);
        const sbom = try renderSbom(allocator, &app);
        defer allocator.free(sbom);

        if (out_path) |path| {
            try writeFile(path, sbom);
        } else {
            try writeStdout(sbom);
            try writeStdout("\n");
        }
        return;
    }

    try usage();
}

fn buildDefaultApp(allocator: std.mem.Allocator) !zigmund.App {
    var app = try zigmund.App.init(allocator, .{
        .title = "Zigmund",
        .version = "0.1.0",
        .servers = &.{"http://127.0.0.1:8000"},
    });

    try app.get("/health", healthHandler, .{
        .summary = "Liveness endpoint",
        .tags = &.{"health"},
    });

    try app.get("/items/{item_id}", getItemHandler, .{
        .summary = "Read one item",
        .tags = &.{"items"},
    });

    try app.websocket("/ws", wsEchoHandler, .{
        .summary = "WebSocket echo endpoint",
    });

    return app;
}

fn healthHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .status = "ok",
    });
}

fn getItemHandler(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const id = req.param("item_id") orelse "unknown";
    return zigmund.Response.json(allocator, .{
        .item_id = id,
    });
}

fn wsEchoHandler(conn: *zigmund.runtime.websocket.Connection, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const msg = conn.receiveSmall() catch return;
    if (msg.opcode == .text) {
        try conn.sendText(msg.data);
    } else {
        try conn.sendBinary(msg.data);
    }
}

const ServeFlagsOwned = struct {
    trusted_proxy_cidrs: std.ArrayListUnmanaged([]const u8) = .empty,

    fn deinit(self: *ServeFlagsOwned, allocator: std.mem.Allocator) void {
        for (self.trusted_proxy_cidrs.items) |cidr| allocator.free(cidr);
        self.trusted_proxy_cidrs.deinit(allocator);
    }
};

fn parseServeFlags(
    allocator: std.mem.Allocator,
    args: anytype,
    cfg: *zigmund.ServerConfig,
    owned: *ServeFlagsOwned,
) !void {
    var tls_cert: ?[]const u8 = null;
    var tls_key: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--host")) {
            cfg.host = args.next() orelse return error.MissingHostValue;
            continue;
        }

        if (std.mem.eql(u8, arg, "--port")) {
            const value = args.next() orelse return error.MissingPortValue;
            cfg.port = try std.fmt.parseInt(u16, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--workers")) {
            const value = args.next() orelse return error.MissingWorkersValue;
            cfg.worker_count = try std.fmt.parseInt(usize, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--max-body-bytes")) {
            const value = args.next() orelse return error.MissingMaxBodyBytesValue;
            cfg.max_body_bytes = try std.fmt.parseInt(usize, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--max-header-bytes")) {
            const value = args.next() orelse return error.MissingMaxHeaderBytesValue;
            cfg.max_header_bytes = try std.fmt.parseInt(usize, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--max-query-bytes")) {
            const value = args.next() orelse return error.MissingMaxQueryBytesValue;
            cfg.max_query_bytes = try std.fmt.parseInt(usize, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--max-connections")) {
            const value = args.next() orelse return error.MissingMaxConnectionsValue;
            cfg.max_connections = try std.fmt.parseInt(usize, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--idle-timeout-ms")) {
            const value = args.next() orelse return error.MissingIdleTimeoutValue;
            cfg.idle_timeout_ms = try std.fmt.parseInt(i32, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--accept-poll-ms")) {
            const value = args.next() orelse return error.MissingAcceptPollValue;
            cfg.accept_poll_interval_ms = try std.fmt.parseInt(i32, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--header-timeout-ms")) {
            const value = args.next() orelse return error.MissingHeaderTimeoutValue;
            cfg.header_timeout_ms = try std.fmt.parseInt(i32, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--body-timeout-ms")) {
            const value = args.next() orelse return error.MissingBodyTimeoutValue;
            cfg.body_timeout_ms = try std.fmt.parseInt(i32, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--shutdown-grace-ms")) {
            const value = args.next() orelse return error.MissingShutdownGraceValue;
            cfg.shutdown_grace_period_ms = try std.fmt.parseInt(u64, value, 10);
            continue;
        }

        if (std.mem.eql(u8, arg, "--trusted-proxy-headers")) {
            cfg.trusted_proxy_headers = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--no-trusted-proxy-headers")) {
            cfg.trusted_proxy_headers = false;
            continue;
        }

        if (std.mem.eql(u8, arg, "--trusted-proxy-forwarded-header")) {
            cfg.trusted_proxy_forwarded_header = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--no-trusted-proxy-forwarded-header")) {
            cfg.trusted_proxy_forwarded_header = false;
            continue;
        }

        if (std.mem.eql(u8, arg, "--trusted-proxy-x-forwarded-headers")) {
            cfg.trusted_proxy_x_forwarded_headers = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--no-trusted-proxy-x-forwarded-headers")) {
            cfg.trusted_proxy_x_forwarded_headers = false;
            continue;
        }

        if (std.mem.eql(u8, arg, "--trusted-proxy-cidrs")) {
            const raw_value = args.next() orelse return error.MissingTrustedProxyCidrsValue;
            var tokens = std.mem.splitScalar(u8, raw_value, ',');
            var appended: usize = 0;

            while (tokens.next()) |token_raw| {
                const token = std.mem.trim(u8, token_raw, " \t");
                if (token.len == 0) continue;

                const owned_cidr = try allocator.dupe(u8, token);
                errdefer allocator.free(owned_cidr);
                try owned.trusted_proxy_cidrs.append(allocator, owned_cidr);
                appended += 1;
            }

            if (appended == 0) return error.MissingTrustedProxyCidrsValue;
            cfg.trusted_proxy_cidrs = owned.trusted_proxy_cidrs.items;
            continue;
        }

        if (std.mem.eql(u8, arg, "--tls-cert")) {
            tls_cert = args.next() orelse return error.MissingTlsCertValue;
            continue;
        }

        if (std.mem.eql(u8, arg, "--tls-key")) {
            tls_key = args.next() orelse return error.MissingTlsKeyValue;
            continue;
        }

        return error.UnknownFlag;
    }

    if (tls_cert == null and tls_key != null) return error.MissingTlsCertValue;
    if (tls_key == null and tls_cert != null) return error.MissingTlsKeyValue;
    if (tls_cert != null and tls_key != null) {
        cfg.tls = .{
            .cert_pem_path = tls_cert.?,
            .key_pem_path = tls_key.?,
        };
    }
}

fn parseRoutesFlags(args: *std.process.ArgIterator) !bool {
    var json_output = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
            continue;
        }
        return error.UnknownFlag;
    }

    return json_output;
}

const OpenApiCommandOptions = struct {
    out_path: ?[]const u8 = null,
    diff_path: ?[]const u8 = null,
    deterministic: bool = false,
};

const CloudProvider = enum {
    generic,
    docker,
    flyio,

    fn asString(self: CloudProvider) []const u8 {
        return switch (self) {
            .generic => "generic",
            .docker => "docker",
            .flyio => "flyio",
        };
    }
};

const CloudCommandOptions = struct {
    out_path: ?[]const u8 = null,
    provider: CloudProvider = .generic,
    emit_dir: ?[]const u8 = null,
};

fn parseOpenApiFlags(args: anytype) !OpenApiCommandOptions {
    var opts: OpenApiCommandOptions = .{};

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out") or std.mem.eql(u8, arg, "--output")) {
            opts.out_path = args.next() orelse return error.MissingOutputPath;
            continue;
        }
        if (std.mem.eql(u8, arg, "--diff")) {
            opts.diff_path = args.next() orelse return error.MissingDiffPath;
            continue;
        }
        if (std.mem.eql(u8, arg, "--deterministic")) {
            opts.deterministic = true;
            continue;
        }
        return error.UnknownFlag;
    }

    return opts;
}

fn parseOutputFlags(args: anytype) !?[]const u8 {
    var out_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out") or std.mem.eql(u8, arg, "--output")) {
            out_path = args.next() orelse return error.MissingOutputPath;
            continue;
        }
        return error.UnknownFlag;
    }

    return out_path;
}

fn parseCloudFlags(args: anytype) !CloudCommandOptions {
    var opts: CloudCommandOptions = .{};

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out") or std.mem.eql(u8, arg, "--output")) {
            opts.out_path = args.next() orelse return error.MissingOutputPath;
            continue;
        }
        if (std.mem.eql(u8, arg, "--provider")) {
            const value = args.next() orelse return error.MissingProviderValue;
            opts.provider = parseCloudProvider(value) orelse return error.InvalidCloudProvider;
            continue;
        }
        if (std.mem.eql(u8, arg, "--emit-dir")) {
            opts.emit_dir = args.next() orelse return error.MissingEmitDirValue;
            continue;
        }
        return error.UnknownFlag;
    }

    return opts;
}

fn parseCloudProvider(value: []const u8) ?CloudProvider {
    if (std.mem.eql(u8, value, "generic")) return .generic;
    if (std.mem.eql(u8, value, "docker")) return .docker;
    if (std.mem.eql(u8, value, "flyio")) return .flyio;
    return null;
}

fn printRoutes(app: *zigmund.App) !void {
    for (app.router.httpRoutes()) |route| {
        try writeStdout(route.method.asString());
        try writeStdout(" ");
        try writeStdout(route.path);
        try writeStdout("\n");
    }

    for (app.router.websocketRoutes()) |route| {
        try writeStdout("websocket ");
        try writeStdout(route.path);
        try writeStdout("\n");
    }
}

fn printRoutesJson(allocator: std.mem.Allocator, app: *zigmund.App) !void {
    const payload = try renderRoutesJson(allocator, app);
    defer allocator.free(payload);

    try writeStdout(payload);
    try writeStdout("\n");
}

fn renderRoutesJson(allocator: std.mem.Allocator, app: *zigmund.App) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var writer = out.writer(allocator);
    try writer.writeAll("[");

    var wrote: usize = 0;

    for (app.router.httpRoutes()) |route| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;

        var max_query_buf: [32]u8 = undefined;
        var max_body_buf: [32]u8 = undefined;
        const strict_validation = jsonOptionalBool(route.options.strict_validation);
        const max_query = jsonOptionalUsize(max_query_buf[0..], route.options.max_query_bytes);
        const max_body = jsonOptionalUsize(max_body_buf[0..], route.options.max_body_bytes);

        try writer.print(
            "{{\"kind\":\"http\",\"method\":{f},\"path\":{f},\"include_in_schema\":{},\"operation_id\":{f},\"name\":{f},\"dependencies\":{d},\"injected_dependencies\":{d},\"strict_validation\":{s},\"max_query_bytes\":{s},\"max_body_bytes\":{s}}}",
            .{
                std.json.fmt(route.method.asString(), .{}),
                std.json.fmt(route.path, .{}),
                route.options.include_in_schema,
                std.json.fmt(route.options.operation_id orelse "", .{}),
                std.json.fmt(route.options.name orelse "", .{}),
                route.options.dependencies.len,
                route.options.injected_dependencies.len,
                strict_validation,
                max_query,
                max_body,
            },
        );
    }

    for (app.router.websocketRoutes()) |route| {
        if (wrote != 0) try writer.writeAll(",");
        wrote += 1;

        var idle_timeout_buf: [32]u8 = undefined;
        var ping_interval_buf: [32]u8 = undefined;
        var pong_timeout_buf: [32]u8 = undefined;
        var max_message_buf: [32]u8 = undefined;
        var max_pending_buf: [32]u8 = undefined;
        var send_timeout_buf: [32]u8 = undefined;

        const idle_timeout = jsonOptionalU64(idle_timeout_buf[0..], route.options.idle_timeout_ms);
        const ping_interval = jsonOptionalU64(ping_interval_buf[0..], route.options.ping_interval_ms);
        const pong_timeout = jsonOptionalU64(pong_timeout_buf[0..], route.options.pong_timeout_ms);
        const max_message = jsonOptionalUsize(max_message_buf[0..], route.options.max_message_bytes);
        const max_pending = jsonOptionalUsize(max_pending_buf[0..], route.options.max_pending_messages);
        const send_timeout = jsonOptionalU64(send_timeout_buf[0..], route.options.send_timeout_ms);

        try writer.print(
            "{{\"kind\":\"websocket\",\"path\":{f},\"operation_id\":{f},\"name\":{f},\"dependencies\":{d},\"injected_dependencies\":{d},\"allowed_origins\":{d},\"require_subprotocol\":{},\"subprotocols\":{d},\"idle_timeout_ms\":{s},\"auto_pong\":{},\"ping_interval_ms\":{s},\"pong_timeout_ms\":{s},\"max_message_bytes\":{s},\"max_pending_messages\":{s},\"send_timeout_ms\":{s}}}",
            .{
                std.json.fmt(route.path, .{}),
                std.json.fmt(route.options.operation_id orelse "", .{}),
                std.json.fmt(route.options.name orelse "", .{}),
                route.options.dependencies.len,
                route.injected_dependencies.len,
                route.options.allowed_origins.len,
                route.options.require_subprotocol,
                route.options.subprotocols.len,
                idle_timeout,
                route.options.auto_pong,
                ping_interval,
                pong_timeout,
                max_message,
                max_pending,
                send_timeout,
            },
        );
    }

    try writer.writeAll("]");
    return out.toOwnedSlice(allocator);
}

fn jsonOptionalBool(value: ?bool) []const u8 {
    if (value) |v| return if (v) "true" else "false";
    return "null";
}

fn jsonOptionalUsize(buf: []u8, value: ?usize) []const u8 {
    if (value) |v| {
        return std.fmt.bufPrint(buf, "{d}", .{v}) catch "null";
    }
    return "null";
}

fn jsonOptionalU64(buf: []u8, value: ?u64) []const u8 {
    if (value) |v| {
        return std.fmt.bufPrint(buf, "{d}", .{v}) catch "null";
    }
    return "null";
}

fn renderCloudPlan(allocator: std.mem.Allocator, app: *zigmund.App, provider: CloudProvider) ![]u8 {
    const openapi = try app.openapi();

    const deploy_descriptor = switch (provider) {
        .generic => "{\"kind\":\"generic\",\"command\":\"zig build run -- serve\",\"artifact_files\":[]}",
        .docker => "{\"kind\":\"docker\",\"command\":\"docker run -p 8000:8000 zigmund/app:latest\",\"artifact_files\":[\"Dockerfile\"]}",
        .flyio => "{\"kind\":\"flyio\",\"command\":\"flyctl deploy\",\"artifact_files\":[\"Dockerfile\",\"fly.toml\"]}",
    };

    return std.fmt.allocPrint(
        allocator,
        "{{\"framework\":{f},\"provider\":{f},\"app_title\":{f},\"app_version\":{f},\"http_routes\":{d},\"websocket_routes\":{d},\"openapi_bytes\":{d},\"serve_hint\":{{\"command\":\"zig build run -- serve\",\"host\":\"127.0.0.1\",\"port\":8000}},\"deploy\":{s}}}",
        .{
            std.json.fmt("zigmund", .{}),
            std.json.fmt(provider.asString(), .{}),
            std.json.fmt(app.cfg.title, .{}),
            std.json.fmt(app.cfg.version, .{}),
            app.router.httpRoutes().len,
            app.router.websocketRoutes().len,
            openapi.len,
            deploy_descriptor,
        },
    );
}

fn emitCloudScaffold(
    allocator: std.mem.Allocator,
    app: *zigmund.App,
    provider: CloudProvider,
    dir_path: []const u8,
) !void {
    if (provider == .generic) return;

    const cwd = std.fs.cwd();
    try cwd.makePath(dir_path);

    const dockerfile_path = try std.fmt.allocPrint(allocator, "{s}/Dockerfile", .{dir_path});
    defer allocator.free(dockerfile_path);
    try writeFile(dockerfile_path, dockerfileTemplate());

    if (provider == .flyio) {
        const app_slug = try cloudAppSlug(allocator, app.cfg.title);
        defer allocator.free(app_slug);

        const fly_toml = try renderFlyToml(allocator, app_slug);
        defer allocator.free(fly_toml);

        const fly_toml_path = try std.fmt.allocPrint(allocator, "{s}/fly.toml", .{dir_path});
        defer allocator.free(fly_toml_path);
        try writeFile(fly_toml_path, fly_toml);
    }
}

fn dockerfileTemplate() []const u8 {
    return 
    \\FROM alpine:3.20
    \\RUN apk add --no-cache libgcc libstdc++ openssl
    \\WORKDIR /app
    \\COPY zig-out/bin/zigmund /app/zigmund
    \\EXPOSE 8000
    \\ENTRYPOINT ["/app/zigmund", "serve", "--host", "0.0.0.0", "--port", "8000"]
    \\
    ;
}

fn renderFlyToml(allocator: std.mem.Allocator, app_slug: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "app = \"{s}\"\nprimary_region = \"iad\"\n\n[build]\n  dockerfile = \"Dockerfile\"\n\n[http_service]\n  internal_port = 8000\n  force_https = true\n  auto_start_machines = true\n  auto_stop_machines = \"stop\"\n  min_machines_running = 0\n  processes = [\"app\"]\n",
        .{app_slug},
    );
}

fn cloudAppSlug(allocator: std.mem.Allocator, title: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var last_dash = false;
    for (title) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try out.append(allocator, std.ascii.toLower(c));
            last_dash = false;
            continue;
        }
        if (!last_dash and out.items.len != 0) {
            try out.append(allocator, '-');
            last_dash = true;
        }
    }

    while (out.items.len > 0 and out.items[out.items.len - 1] == '-') {
        _ = out.pop();
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "zigmund-app");
    }

    return out.toOwnedSlice(allocator);
}

fn usage() !void {
    try writeStdout(
        "Usage: zigmund <command> [options]\n" ++
            "Commands:\n" ++
            "  serve [--host <host>] [--port <port>] [--workers <n>] [--max-body-bytes <n>] [--max-header-bytes <n>] [--max-query-bytes <n>] [--max-connections <n>] [--idle-timeout-ms <n>] [--accept-poll-ms <n>] [--header-timeout-ms <n>] [--body-timeout-ms <n>] [--shutdown-grace-ms <n>] [--trusted-proxy-headers|--no-trusted-proxy-headers] [--trusted-proxy-forwarded-header|--no-trusted-proxy-forwarded-header] [--trusted-proxy-x-forwarded-headers|--no-trusted-proxy-x-forwarded-headers] [--trusted-proxy-cidrs <cidr[,cidr...]>] [--tls-cert <pem>] [--tls-key <pem>]\n" ++
            "  dev   [--watch-ms <n>] [--host <host>] [--port <port>] [--workers <n>] [--max-body-bytes <n>] [--max-header-bytes <n>] [--max-query-bytes <n>] [--max-connections <n>] [--idle-timeout-ms <n>] [--accept-poll-ms <n>] [--header-timeout-ms <n>] [--body-timeout-ms <n>] [--shutdown-grace-ms <n>] [--trusted-proxy-headers|--no-trusted-proxy-headers] [--trusted-proxy-forwarded-header|--no-trusted-proxy-forwarded-header] [--trusted-proxy-x-forwarded-headers|--no-trusted-proxy-x-forwarded-headers] [--trusted-proxy-cidrs <cidr[,cidr...]>] [--tls-cert <pem>] [--tls-key <pem>]\n" ++
            "  routes [--json]\n" ++
            "  openapi [--deterministic] [--out <path>] [--diff <path>]\n" ++
            "  cloud [--provider <generic|docker|flyio>] [--out <path>] [--emit-dir <dir>]\n" ++
            "  sbom [--out <path>]\n",
    );
}

fn renderSbom(allocator: std.mem.Allocator, app: *zigmund.App) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"bomFormat\":\"CycloneDX\",\"specVersion\":\"1.5\",\"version\":1,\"metadata\":{{\"component\":{{\"type\":\"application\",\"name\":{f},\"version\":{f},\"licenses\":[{{\"license\":{{\"id\":\"MIT\"}}}}]}}}},\"components\":[{{\"type\":\"framework\",\"name\":\"zig\",\"version\":{f}}},{{\"type\":\"library\",\"name\":\"openssl\",\"version\":\"runtime\"}}]}}",
        .{
            std.json.fmt(app.cfg.title, .{}),
            std.json.fmt(app.cfg.version, .{}),
            std.json.fmt(builtin.zig_version_string, .{}),
        },
    );
}

const DevConfig = struct {
    watch_interval_ms: u64 = 400,
    serve_args: [][]const u8,

    fn deinit(self: *DevConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.serve_args);
    }
};

const DevProcess = struct {
    child: std.process.Child,
    argv: [][]const u8,

    fn deinit(self: *DevProcess, allocator: std.mem.Allocator) void {
        allocator.free(self.argv);
    }
};

fn runDevMode(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    var cfg = try parseDevFlags(allocator, args);
    defer cfg.deinit(allocator);

    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);

    var fingerprint = try workspaceFingerprint(allocator);
    var proc = try spawnServeProcess(allocator, exe_path, cfg.serve_args);
    defer {
        stopServeProcess(&proc);
        proc.deinit(allocator);
    }

    std.log.info("dev mode watching source tree (interval={d}ms)", .{cfg.watch_interval_ms});

    while (true) {
        std.Thread.sleep(cfg.watch_interval_ms * std.time.ns_per_ms);

        const current = workspaceFingerprint(allocator) catch |err| {
            std.log.warn("dev watch fingerprint failed: {s}", .{@errorName(err)});
            continue;
        };
        if (current == fingerprint) continue;

        fingerprint = current;
        std.log.info("change detected, restarting server", .{});

        stopServeProcess(&proc);
        proc.deinit(allocator);
        proc = try spawnServeProcess(allocator, exe_path, cfg.serve_args);
    }
}

fn parseDevFlags(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !DevConfig {
    var forwarded: std.ArrayList([]const u8) = .empty;
    errdefer forwarded.deinit(allocator);

    var watch_interval_ms: u64 = 400;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--watch-ms")) {
            const raw = args.next() orelse return error.MissingWatchIntervalValue;
            watch_interval_ms = try std.fmt.parseInt(u64, raw, 10);
            continue;
        }
        try forwarded.append(allocator, arg);
    }

    if (watch_interval_ms == 0) watch_interval_ms = 50;

    return .{
        .watch_interval_ms = watch_interval_ms,
        .serve_args = try forwarded.toOwnedSlice(allocator),
    };
}

fn spawnServeProcess(
    allocator: std.mem.Allocator,
    exe_path: []const u8,
    serve_args: []const []const u8,
) !DevProcess {
    const argv = try allocator.alloc([]const u8, 2 + serve_args.len);
    errdefer allocator.free(argv);

    argv[0] = exe_path;
    argv[1] = "serve";
    @memcpy(argv[2..], serve_args);

    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    try child.spawn();

    return .{
        .child = child,
        .argv = argv,
    };
}

fn stopServeProcess(proc: *DevProcess) void {
    _ = proc.child.kill() catch {};
    _ = proc.child.wait() catch {};
}

fn workspaceFingerprint(allocator: std.mem.Allocator) !u64 {
    const roots = [_][]const u8{
        "build.zig",
        "build.zig.zon",
        "src",
        "tests",
        "examples",
        "tools",
    };

    const cwd = std.fs.cwd();
    var hasher = std.hash.Wyhash.init(0);

    for (roots) |root| {
        const root_stat = cwd.statFile(root) catch continue;
        hasher.update(root);
        hashStat(&hasher, root_stat);

        if (root_stat.kind == .directory) {
            try hashDirectoryTree(allocator, root, &hasher);
        }
    }

    return hasher.final();
}

fn hashDirectoryTree(
    allocator: std.mem.Allocator,
    root: []const u8,
    hasher: *std.hash.Wyhash,
) !void {
    var dir = try std.fs.cwd().openDir(root, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        hasher.update(root);
        hasher.update("/");
        hasher.update(entry.path);

        const stat = dir.statFile(entry.path) catch continue;
        hashStat(hasher, stat);
    }
}

fn hashStat(hasher: *std.hash.Wyhash, stat: std.fs.File.Stat) void {
    var size = stat.size;
    var mtime = stat.mtime;
    var kind_tag: u16 = @intFromEnum(stat.kind);

    hasher.update(std.mem.asBytes(&size));
    hasher.update(std.mem.asBytes(&mtime));
    hasher.update(std.mem.asBytes(&kind_tag));
}

fn writeStdout(bytes: []const u8) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    try stdout_writer.interface.writeAll(bytes);
    try stdout_writer.interface.flush();
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data = bytes,
    });
}

fn assertOpenApiSnapshotFile(
    allocator: std.mem.Allocator,
    actual: []const u8,
    snapshot_path: []const u8,
) !void {
    const expected = std.fs.cwd().readFileAlloc(
        allocator,
        snapshot_path,
        32 * 1024 * 1024,
    ) catch |err| switch (err) {
        error.FileNotFound => return error.OpenApiSnapshotMissing,
        else => return err,
    };
    defer allocator.free(expected);

    assertOpenApiSnapshot(expected, actual) catch |err| switch (err) {
        error.OpenApiSnapshotMismatch => {
            const first_diff = firstDiffIndex(expected, actual) orelse @min(expected.len, actual.len);
            std.log.err(
                "openapi snapshot mismatch: path={s} expected_len={d} actual_len={d} first_diff={d}",
                .{ snapshot_path, expected.len, actual.len, first_diff },
            );
            return err;
        },
        else => return err,
    };
}

fn assertOpenApiSnapshot(
    expected: []const u8,
    actual: []const u8,
) !void {
    if (std.mem.eql(u8, expected, actual)) return;
    return error.OpenApiSnapshotMismatch;
}

fn firstDiffIndex(expected: []const u8, actual: []const u8) ?usize {
    const min_len = @min(expected.len, actual.len);
    var idx: usize = 0;
    while (idx < min_len) : (idx += 1) {
        if (expected[idx] != actual[idx]) return idx;
    }

    if (expected.len == actual.len) return null;
    return min_len;
}

test "default app wires base routes" {
    var app = try buildDefaultApp(std.testing.allocator);
    defer app.deinit();

    try std.testing.expect(app.router.httpRoutes().len >= 2);
    try std.testing.expect(app.router.websocketRoutes().len >= 1);
}

test "routes json renderer includes http and websocket routes" {
    var app = try buildDefaultApp(std.testing.allocator);
    defer app.deinit();

    const payload = try renderRoutesJson(std.testing.allocator, &app);
    defer std.testing.allocator.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"kind\":\"http\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"method\":\"get\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"include_in_schema\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"strict_validation\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"max_query_bytes\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"max_body_bytes\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"kind\":\"websocket\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"path\":\"/ws\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"require_subprotocol\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"idle_timeout_ms\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"auto_pong\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"ping_interval_ms\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"max_message_bytes\":null") != null);
}

test "cloud plan renderer outputs route counts and openapi size" {
    var app = try buildDefaultApp(std.testing.allocator);
    defer app.deinit();

    const plan = try renderCloudPlan(std.testing.allocator, &app, .generic);
    defer std.testing.allocator.free(plan);

    try std.testing.expect(std.mem.indexOf(u8, plan, "\"framework\":\"zigmund\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"provider\":\"generic\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"http_routes\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"websocket_routes\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"openapi_bytes\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, plan, "\"deploy\":{\"kind\":\"generic\"") != null);
}

test "cloud plan renderer supports docker and flyio providers" {
    var app = try buildDefaultApp(std.testing.allocator);
    defer app.deinit();

    const docker_plan = try renderCloudPlan(std.testing.allocator, &app, .docker);
    defer std.testing.allocator.free(docker_plan);
    try std.testing.expect(std.mem.indexOf(u8, docker_plan, "\"provider\":\"docker\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, docker_plan, "\"command\":\"docker run -p 8000:8000 zigmund/app:latest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, docker_plan, "\"artifact_files\":[\"Dockerfile\"]") != null);

    const flyio_plan = try renderCloudPlan(std.testing.allocator, &app, .flyio);
    defer std.testing.allocator.free(flyio_plan);
    try std.testing.expect(std.mem.indexOf(u8, flyio_plan, "\"provider\":\"flyio\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, flyio_plan, "\"command\":\"flyctl deploy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, flyio_plan, "\"artifact_files\":[\"Dockerfile\",\"fly.toml\"]") != null);
}

test "parse cloud flags supports provider output and scaffold args" {
    var iter = (try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "--provider flyio --out deploy-plan.json --emit-dir deploy",
    ));
    defer iter.deinit();

    const opts = try parseCloudFlags(&iter);
    try std.testing.expectEqual(CloudProvider.flyio, opts.provider);
    try std.testing.expectEqualStrings("deploy-plan.json", opts.out_path.?);
    try std.testing.expectEqualStrings("deploy", opts.emit_dir.?);
}

test "cloud app slug and scaffold templates are deterministic" {
    const slug = try cloudAppSlug(std.testing.allocator, "Zigmund API (Prod)");
    defer std.testing.allocator.free(slug);
    try std.testing.expectEqualStrings("zigmund-api-prod", slug);

    const fallback = try cloudAppSlug(std.testing.allocator, "____");
    defer std.testing.allocator.free(fallback);
    try std.testing.expectEqualStrings("zigmund-app", fallback);

    const dockerfile = dockerfileTemplate();
    try std.testing.expect(std.mem.indexOf(u8, dockerfile, "ENTRYPOINT") != null);
    try std.testing.expect(std.mem.indexOf(u8, dockerfile, "zig-out/bin/zigmund") != null);

    const fly_toml = try renderFlyToml(std.testing.allocator, "zigmund-api-prod");
    defer std.testing.allocator.free(fly_toml);
    try std.testing.expect(std.mem.indexOf(u8, fly_toml, "app = \"zigmund-api-prod\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fly_toml, "internal_port = 8000") != null);
}

test "emit cloud scaffold writes provider files" {
    var app = try buildDefaultApp(std.testing.allocator);
    defer app.deinit();

    const unique_id = std.time.nanoTimestamp();
    const emit_dir = try std.fmt.allocPrint(std.testing.allocator, "zig-cache/test-cloud-{d}", .{unique_id});
    defer std.testing.allocator.free(emit_dir);
    std.fs.cwd().deleteTree(emit_dir) catch {};
    defer std.fs.cwd().deleteTree(emit_dir) catch {};

    try emitCloudScaffold(std.testing.allocator, &app, .flyio, emit_dir);

    const dockerfile_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/Dockerfile", .{emit_dir});
    defer std.testing.allocator.free(dockerfile_path);
    const fly_toml_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/fly.toml", .{emit_dir});
    defer std.testing.allocator.free(fly_toml_path);

    const dockerfile = try std.fs.cwd().readFileAlloc(std.testing.allocator, dockerfile_path, 16 * 1024);
    defer std.testing.allocator.free(dockerfile);
    try std.testing.expect(std.mem.indexOf(u8, dockerfile, "ENTRYPOINT") != null);

    const fly_toml = try std.fs.cwd().readFileAlloc(std.testing.allocator, fly_toml_path, 16 * 1024);
    defer std.testing.allocator.free(fly_toml);
    try std.testing.expect(std.mem.indexOf(u8, fly_toml, "app = \"zigmund\"") != null);

    const generic_dir = try std.fmt.allocPrint(std.testing.allocator, "zig-cache/test-cloud-generic-{d}", .{unique_id});
    defer std.testing.allocator.free(generic_dir);
    std.fs.cwd().deleteTree(generic_dir) catch {};
    defer std.fs.cwd().deleteTree(generic_dir) catch {};

    try emitCloudScaffold(std.testing.allocator, &app, .generic, generic_dir);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().openDir(generic_dir, .{}));
}

test "sbom renderer outputs cyclonedx metadata and component licenses" {
    var app = try buildDefaultApp(std.testing.allocator);
    defer app.deinit();

    const sbom = try renderSbom(std.testing.allocator, &app);
    defer std.testing.allocator.free(sbom);

    try std.testing.expect(std.mem.indexOf(u8, sbom, "\"bomFormat\":\"CycloneDX\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbom, "\"specVersion\":\"1.5\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbom, "\"licenses\":[{\"license\":{\"id\":\"MIT\"}}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbom, "\"name\":\"zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sbom, "\"name\":\"openssl\"") != null);
}

test "openapi snapshot assertion passes when docs match" {
    try assertOpenApiSnapshot("{}", "{}");
}

test "openapi snapshot assertion fails when docs differ" {
    try std.testing.expectError(
        error.OpenApiSnapshotMismatch,
        assertOpenApiSnapshot("{\"a\":1}", "{\"a\":2}"),
    );
    try std.testing.expectEqual(@as(?usize, 5), firstDiffIndex("{\"a\":1}", "{\"a\":2}"));
}

test "parse openapi flags supports deterministic out and diff options" {
    var iter = (try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "--deterministic --out openapi.json --diff baseline.json",
    ));
    defer iter.deinit();

    const opts = try parseOpenApiFlags(&iter);
    try std.testing.expect(opts.deterministic);
    try std.testing.expectEqualStrings("openapi.json", opts.out_path.?);
    try std.testing.expectEqualStrings("baseline.json", opts.diff_path.?);
}

test "parse serve flags supports header timeout option" {
    var cfg = zigmund.ServerConfig{};
    var owned: ServeFlagsOwned = .{};
    defer owned.deinit(std.testing.allocator);

    var iter = (try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "--header-timeout-ms 321 --body-timeout-ms 777 --idle-timeout-ms 654",
    ));
    defer iter.deinit();

    try parseServeFlags(std.testing.allocator, &iter, &cfg, &owned);
    try std.testing.expectEqual(@as(i32, 321), cfg.header_timeout_ms);
    try std.testing.expectEqual(@as(i32, 777), cfg.body_timeout_ms);
    try std.testing.expectEqual(@as(i32, 654), cfg.idle_timeout_ms);
}

test "parse serve flags supports max query bytes option" {
    var cfg = zigmund.ServerConfig{};
    var owned: ServeFlagsOwned = .{};
    defer owned.deinit(std.testing.allocator);

    var iter = (try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "--max-query-bytes 4096",
    ));
    defer iter.deinit();

    try parseServeFlags(std.testing.allocator, &iter, &cfg, &owned);
    try std.testing.expectEqual(@as(usize, 4096), cfg.max_query_bytes);
}

test "parse serve flags supports trusted proxy header toggles" {
    var enabled_cfg = zigmund.ServerConfig{};
    var enabled_owned: ServeFlagsOwned = .{};
    defer enabled_owned.deinit(std.testing.allocator);
    var enabled_iter = (try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "--trusted-proxy-headers",
    ));
    defer enabled_iter.deinit();

    try parseServeFlags(std.testing.allocator, &enabled_iter, &enabled_cfg, &enabled_owned);
    try std.testing.expect(enabled_cfg.trusted_proxy_headers);

    var disabled_cfg = zigmund.ServerConfig{ .trusted_proxy_headers = true };
    var disabled_owned: ServeFlagsOwned = .{};
    defer disabled_owned.deinit(std.testing.allocator);
    var disabled_iter = (try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "--no-trusted-proxy-headers",
    ));
    defer disabled_iter.deinit();

    try parseServeFlags(std.testing.allocator, &disabled_iter, &disabled_cfg, &disabled_owned);
    try std.testing.expect(!disabled_cfg.trusted_proxy_headers);
}

test "parse serve flags supports independent forwarded and x-forwarded header toggles" {
    var cfg = zigmund.ServerConfig{};
    var owned: ServeFlagsOwned = .{};
    defer owned.deinit(std.testing.allocator);
    var iter = (try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "--no-trusted-proxy-forwarded-header --trusted-proxy-x-forwarded-headers",
    ));
    defer iter.deinit();

    try parseServeFlags(std.testing.allocator, &iter, &cfg, &owned);
    try std.testing.expect(!cfg.trusted_proxy_forwarded_header);
    try std.testing.expect(cfg.trusted_proxy_x_forwarded_headers);

    var cfg_second = zigmund.ServerConfig{};
    var owned_second: ServeFlagsOwned = .{};
    defer owned_second.deinit(std.testing.allocator);
    var iter_second = (try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "--trusted-proxy-forwarded-header --no-trusted-proxy-x-forwarded-headers",
    ));
    defer iter_second.deinit();

    try parseServeFlags(std.testing.allocator, &iter_second, &cfg_second, &owned_second);
    try std.testing.expect(cfg_second.trusted_proxy_forwarded_header);
    try std.testing.expect(!cfg_second.trusted_proxy_x_forwarded_headers);
}

test "parse serve flags supports trusted proxy cidr allowlist values" {
    var cfg = zigmund.ServerConfig{};
    var owned: ServeFlagsOwned = .{};
    defer owned.deinit(std.testing.allocator);

    var iter = (try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "--trusted-proxy-headers --trusted-proxy-cidrs 10.0.0.0/8,192.168.0.0/16 --trusted-proxy-cidrs 127.0.0.1/32",
    ));
    defer iter.deinit();

    try parseServeFlags(std.testing.allocator, &iter, &cfg, &owned);
    try std.testing.expect(cfg.trusted_proxy_headers);
    try std.testing.expectEqual(@as(usize, 3), cfg.trusted_proxy_cidrs.len);
    try std.testing.expectEqualStrings("10.0.0.0/8", cfg.trusted_proxy_cidrs[0]);
    try std.testing.expectEqualStrings("192.168.0.0/16", cfg.trusted_proxy_cidrs[1]);
    try std.testing.expectEqualStrings("127.0.0.1/32", cfg.trusted_proxy_cidrs[2]);
}

test "routes json renderer includes operation and dependency metadata" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "routes-json-meta",
        .version = "0.0.1",
    });
    defer app.deinit();

    const auth_dep = struct {
        fn resolve(req: *zigmund.Request, allocator: std.mem.Allocator) !?[]const u8 {
            _ = req;
            _ = allocator;
            return "token";
        }
    };
    const ws_handler = struct {
        fn run(
            conn: *zigmund.runtime.websocket.Connection,
            auth: zigmund.Depends(auth_dep.resolve, .{ .name = "auth" }),
            allocator: std.mem.Allocator,
        ) !void {
            _ = conn;
            _ = auth;
            _ = allocator;
        }
    };

    try app.addDependency("auth", auth_dep.resolve);
    try app.get("/meta", healthHandler, .{
        .name = "meta_route",
        .operation_id = "get_meta",
        .strict_validation = true,
        .max_query_bytes = 1024,
        .max_body_bytes = 2048,
        .dependencies = &.{.{ .name = "auth" }},
    });
    try app.websocket("/ws-meta", ws_handler.run, .{
        .name = "meta_ws",
        .operation_id = "websocket_meta",
        .allowed_origins = &.{"https://example.com"},
        .subprotocols = &.{"chat.v1"},
        .require_subprotocol = true,
        .idle_timeout_ms = 45_000,
        .auto_pong = false,
        .ping_interval_ms = 5_000,
        .pong_timeout_ms = 1_500,
        .max_message_bytes = 8192,
        .max_pending_messages = 64,
        .send_timeout_ms = 2_000,
    });

    const payload = try renderRoutesJson(std.testing.allocator, &app);
    defer std.testing.allocator.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"operation_id\":\"get_meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"name\":\"meta_route\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"dependencies\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"strict_validation\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"max_query_bytes\":1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"max_body_bytes\":2048") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"operation_id\":\"websocket_meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"injected_dependencies\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"require_subprotocol\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"allowed_origins\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"subprotocols\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"idle_timeout_ms\":45000") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"auto_pong\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"ping_interval_ms\":5000") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"pong_timeout_ms\":1500") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"max_message_bytes\":8192") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"max_pending_messages\":64") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"send_timeout_ms\":2000") != null);
}
