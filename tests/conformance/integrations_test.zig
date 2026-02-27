const std = @import("std");
const zigmund = @import("zigmund");

test "settings integration loads defaults and typed values from env map" {
    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();

    try env_map.put("APP_NAME", "zigmund");
    try env_map.put("PORT", "9000");
    try env_map.put("FEATURE_FLAG", "true");

    const specs = [_]zigmund.SettingSpec{
        .{ .key = "app_name", .env = "APP_NAME" },
        .{ .key = "port", .env = "PORT" },
        .{ .key = "feature_flag", .env = "FEATURE_FLAG" },
        .{ .key = "env", .env = "ENV", .required = false, .default_value = "dev" },
    };

    var settings = try zigmund.loadSettingsFromEnvMap(std.testing.allocator, &specs, &env_map);
    defer settings.deinit();

    try std.testing.expectEqualStrings("zigmund", settings.get("app_name").?);
    try std.testing.expectEqual(@as(u16, 9000), try settings.getInt(u16, "port"));
    try std.testing.expectEqual(true, try settings.getBool("feature_flag"));
    try std.testing.expectEqualStrings("dev", settings.get("env").?);
}

test "templates integration renders html payload from bindings" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "welcome.html",
        .data = "<h1>Hello {{ name }}</h1><p>ID={{id}}</p>",
    });

    const templates_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(templates_dir);

    var templates = try zigmund.TemplatesIntegration.init(std.testing.allocator, templates_dir);
    defer templates.deinit();

    const bindings = [_]zigmund.TemplateBinding{
        .{ .key = "name", .value = .{ .string = "Toto" } },
        .{ .key = "id", .value = .{ .unsigned = 7 } },
    };

    var res = try templates.renderHtmlResponse("welcome.html", &bindings);
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("text/html; charset=utf-8", res.content_type);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "<h1>Hello Toto</h1>") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "<p>ID=7</p>") != null);
}

test "static files integration serves files and supports conditional requests" {
    zigmund.integrations.static_files.clearMountsForTesting();
    defer zigmund.integrations.static_files.clearMountsForTesting();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("css");
    try tmp.dir.writeFile(.{ .sub_path = "index.html", .data = "<h1>docs</h1>" });
    try tmp.dir.writeFile(.{ .sub_path = "css/site.css", .data = "body{margin:0}" });

    const static_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(static_root);

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "static",
        .version = "0.0.1",
    });
    defer app.deinit();

    try zigmund.mountStaticFiles(&app, "/assets", static_root, .{});

    var file_res = try app.dispatchSynthetic(.GET, "/assets/css/site.css", "");
    defer file_res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, file_res.status);
    try std.testing.expectEqualStrings("body{margin:0}", file_res.body);
    const etag = file_res.header("etag") orelse return error.TestUnexpectedResult;
    const last_modified = file_res.header("last-modified") orelse return error.TestUnexpectedResult;

    const etag_headers = [_]std.http.Header{
        .{ .name = "if-none-match", .value = etag },
    };
    var etag_not_modified = try app.dispatchSyntheticWithHeaders(.GET, "/assets/css/site.css", "", &etag_headers);
    defer etag_not_modified.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_modified, etag_not_modified.status);

    const lm_headers = [_]std.http.Header{
        .{ .name = "if-modified-since", .value = last_modified },
    };
    var lm_not_modified = try app.dispatchSyntheticWithHeaders(.GET, "/assets/css/site.css", "", &lm_headers);
    defer lm_not_modified.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_modified, lm_not_modified.status);

    var blocked = try app.dispatchSynthetic(.GET, "/assets/../secrets.txt", "");
    defer blocked.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_found, blocked.status);
}

test "graphql integration mounts endpoint and executes query payload" {
    zigmund.integrations.graphql.clearRegistrationsForTesting();
    defer zigmund.integrations.graphql.clearRegistrationsForTesting();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "graphql",
        .version = "0.0.1",
    });
    defer app.deinit();

    const Exec = struct {
        fn run(
            query: []const u8,
            operation_name: ?[]const u8,
            variables_json: ?[]const u8,
            req: *zigmund.Request,
            allocator: std.mem.Allocator,
        ) !zigmund.Response {
            _ = req;
            return zigmund.Response.json(allocator, .{
                .query = query,
                .operation = operation_name orelse "",
                .variables = variables_json orelse "",
            });
        }
    };

    try zigmund.mountGraphQl(&app, "/graphql", Exec.run, .{});

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json; charset=utf-8" },
    };
    const body =
        \\{"query":"query Ping { ping }","operationName":"Ping","variables":{"tenant":"acme"}}
    ;

    var res = try app.dispatchSyntheticWithHeaders(.POST, "/graphql", body, &headers);
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"query\":\"query Ping { ping }\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"operation\":\"Ping\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\\\"tenant\\\":\\\"acme\\\"") != null);

    var playground = try app.dispatchSynthetic(.GET, "/graphql", "");
    defer playground.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, playground.status);
    try std.testing.expect(std.mem.indexOf(u8, playground.body, "GraphQL Playground") != null);
}

test "sql session provider dependency lifecycle is deterministic" {
    const Provider = zigmund.SqlSessionProvider("postgres://svc@localhost/main");
    Provider.resetForTesting();

    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "sql-session",
        .version = "0.0.1",
    });
    defer app.deinit();

    try Provider.register(&app, "db_session");

    const H = struct {
        fn run(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
            return zigmund.Response.json(allocator, .{
                .db = req.dependency("db_session") orelse "",
            });
        }
    };

    try app.get("/db", H.run, .{
        .dependencies = &.{.{ .name = "db_session" }},
    });

    try std.testing.expectEqual(@as(usize, 0), Provider.activeCount());
    var res = try app.dispatchSynthetic(.GET, "/db", "");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "postgres://svc@localhost/main") != null);
    try std.testing.expectEqual(@as(usize, 0), Provider.activeCount());
}

test "compatibility adapters apply proxy trust policy to server config" {
    var cfg: zigmund.ServerConfig = .{
        .trusted_proxy_headers = true,
        .trusted_proxy_forwarded_header = true,
        .trusted_proxy_x_forwarded_headers = true,
        .trusted_proxy_cidrs = &.{"127.0.0.1/32"},
    };

    const proxy_mode = zigmund.CompatibilityAdapters{
        .enable_proxy_mode = true,
        .trusted_proxy_headers = true,
        .trusted_proxy_forwarded_header = true,
        .trusted_proxy_x_forwarded_headers = false,
        .trusted_proxy_cidrs = &.{
            "10.0.0.0/8",
            "192.168.0.0/16",
        },
    };
    proxy_mode.applyToServerConfig(&cfg);

    try std.testing.expect(cfg.trusted_proxy_headers);
    try std.testing.expect(cfg.trusted_proxy_forwarded_header);
    try std.testing.expect(!cfg.trusted_proxy_x_forwarded_headers);
    try std.testing.expectEqual(@as(usize, 2), cfg.trusted_proxy_cidrs.len);
    try std.testing.expectEqualStrings("10.0.0.0/8", cfg.trusted_proxy_cidrs[0]);

    const direct_mode = zigmund.CompatibilityAdapters{
        .enable_proxy_mode = false,
    };
    direct_mode.applyToServerConfig(&cfg);

    try std.testing.expect(!cfg.trusted_proxy_headers);
    try std.testing.expect(!cfg.trusted_proxy_forwarded_header);
    try std.testing.expect(!cfg.trusted_proxy_x_forwarded_headers);
    try std.testing.expectEqual(@as(usize, 0), cfg.trusted_proxy_cidrs.len);
}
