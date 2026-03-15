const std = @import("std");
const types = @import("../core/types.zig");

pub const swagger_ui_version = "5.17.14";
pub const redoc_version = "2.4.0";

const swagger_template = @embedFile("../assets/docs-ui/swagger/index.html");
const redoc_template = @embedFile("../assets/docs-ui/redoc/index.html");

const swagger_bundle_js = @embedFile("../assets/docs-ui/swagger/swagger-ui-bundle.js");
const swagger_standalone_js = @embedFile("../assets/docs-ui/swagger/swagger-ui-standalone-preset.js");
const swagger_css = @embedFile("../assets/docs-ui/swagger/swagger-ui.css");
const redoc_standalone_js = @embedFile("../assets/docs-ui/redoc/redoc.standalone.js");

const swagger_dark_theme_css =
    "body.zigmund-docs { background: #0f172a !important; }\n" ++
    "body.zigmund-docs .swagger-ui, body.zigmund-docs .swagger-ui .info .title { color: #e2e8f0; }\n" ++
    "body.zigmund-docs .swagger-ui .topbar { background-color: #111827; }\n" ++
    "body.zigmund-docs .swagger-ui .scheme-container { background: #111827; box-shadow: none; }\n" ++
    "body.zigmund-docs .swagger-ui .opblock .opblock-summary { border-color: rgba(148, 163, 184, 0.35); }\n";

const redoc_dark_theme_css =
    "body.zigmund-redoc { background: #0f172a; color: #e2e8f0; }\n" ++
    "body.zigmund-redoc #redoc-container { min-height: 100vh; }\n";

const Replacement = struct {
    needle: []const u8,
    value: []const u8,
};

pub fn renderSwagger(
    allocator: std.mem.Allocator,
    app_title: []const u8,
    openapi_url: []const u8,
    cfg: types.SwaggerUiConfig,
) ![]u8 {
    const doc_title_raw = cfg.title orelse app_title;

    const doc_title = try escapeHtml(allocator, doc_title_raw);
    defer allocator.free(doc_title);

    const openapi_url_json = try jsonString(allocator, openapi_url);
    defer allocator.free(openapi_url_json);

    const doc_expansion_json = try jsonString(allocator, swaggerDocExpansionString(cfg.doc_expansion));
    defer allocator.free(doc_expansion_json);

    const theme_overrides = switch (cfg.theme) {
        .light => "",
        .dark => swagger_dark_theme_css,
    };

    var oauth2_redirect_line: ?[]u8 = null;
    defer if (oauth2_redirect_line) |line| allocator.free(line);
    if (cfg.oauth2_redirect_url) |redirect_url| {
        const url_json = try jsonString(allocator, redirect_url);
        defer allocator.free(url_json);
        oauth2_redirect_line = try std.fmt.allocPrint(
            allocator,
            "oauth2RedirectUrl: {s},\n        ",
            .{url_json},
        );
    }

    return applyReplacements(allocator, swagger_template, &.{
        .{ .needle = "__DOC_TITLE__", .value = doc_title },
        .{ .needle = "__OPENAPI_URL_JSON__", .value = openapi_url_json },
        .{ .needle = "__DEEP_LINKING__", .value = boolLiteral(cfg.deep_linking) },
        .{ .needle = "__PERSIST_AUTHORIZATION__", .value = boolLiteral(cfg.persist_authorization) },
        .{ .needle = "__DISPLAY_OPERATION_ID__", .value = boolLiteral(cfg.display_operation_id) },
        .{ .needle = "__DOC_EXPANSION_JSON__", .value = doc_expansion_json },
        .{ .needle = "__OAUTH2_REDIRECT_URL__", .value = if (oauth2_redirect_line) |line| line else "" },
        .{ .needle = "__SWAGGER_CSS__", .value = swagger_css },
        .{ .needle = "__SWAGGER_BUNDLE_JS__", .value = swagger_bundle_js },
        .{ .needle = "__SWAGGER_STANDALONE_JS__", .value = swagger_standalone_js },
        .{ .needle = "__SWAGGER_THEME_OVERRIDES__", .value = theme_overrides },
    });
}

pub fn renderRedoc(
    allocator: std.mem.Allocator,
    app_title: []const u8,
    openapi_url: []const u8,
    cfg: types.RedocUiConfig,
) ![]u8 {
    const doc_title_raw = cfg.title orelse app_title;
    const doc_title = try escapeHtml(allocator, doc_title_raw);
    defer allocator.free(doc_title);

    const openapi_url_json = try jsonString(allocator, openapi_url);
    defer allocator.free(openapi_url_json);

    const theme_overrides = switch (cfg.theme) {
        .light => "",
        .dark => redoc_dark_theme_css,
    };

    return applyReplacements(allocator, redoc_template, &.{
        .{ .needle = "__DOC_TITLE__", .value = doc_title },
        .{ .needle = "__OPENAPI_URL_JSON__", .value = openapi_url_json },
        .{ .needle = "__HIDE_DOWNLOAD_BUTTON__", .value = boolLiteral(cfg.hide_download_button) },
        .{ .needle = "__DISABLE_SEARCH__", .value = boolLiteral(cfg.disable_search) },
        .{ .needle = "__REDOC_STANDALONE_JS__", .value = redoc_standalone_js },
        .{ .needle = "__REDOC_THEME_OVERRIDES__", .value = theme_overrides },
    });
}

fn swaggerDocExpansionString(expansion: types.SwaggerDocExpansion) []const u8 {
    return switch (expansion) {
        .list => "list",
        .full => "full",
        .none => "none",
    };
}

fn boolLiteral(value: bool) []const u8 {
    return if (value) "true" else "false";
}

fn applyReplacements(
    allocator: std.mem.Allocator,
    template: []const u8,
    replacements: []const Replacement,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var idx: usize = 0;
    while (idx < template.len) {
        var matched = false;
        for (replacements) |replacement| {
            if (!std.mem.startsWith(u8, template[idx..], replacement.needle)) continue;

            try out.appendSlice(allocator, replacement.value);
            idx += replacement.needle.len;
            matched = true;
            break;
        }

        if (matched) continue;

        try out.append(allocator, template[idx]);
        idx += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn jsonString(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{})});
}

fn escapeHtml(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    for (value) |ch| {
        switch (ch) {
            '&' => try out.appendSlice(allocator, "&amp;"),
            '<' => try out.appendSlice(allocator, "&lt;"),
            '>' => try out.appendSlice(allocator, "&gt;"),
            '"' => try out.appendSlice(allocator, "&quot;"),
            '\'' => try out.appendSlice(allocator, "&#39;"),
            else => try out.append(allocator, ch),
        }
    }

    return out.toOwnedSlice(allocator);
}

test "swagger docs template is rendered with embedded assets and options" {
    const html = try renderSwagger(std.testing.allocator, "Zigmund", "/openapi.json", .{
        .title = "Internal Docs",
        .persist_authorization = true,
        .deep_linking = false,
        .display_operation_id = true,
        .doc_expansion = .full,
        .theme = .dark,
    });
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "__OPENAPI_URL_JSON__") == null);
    try std.testing.expect(std.mem.indexOf(u8, html, "SwaggerUIBundle") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "persistAuthorization: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "deepLinking: false") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "docExpansion: \"full\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Internal Docs") != null);
}

test "redoc docs template is rendered with embedded assets and options" {
    const html = try renderRedoc(std.testing.allocator, "Zigmund", "/openapi.json", .{
        .title = "Internal ReDoc",
        .hide_download_button = true,
        .disable_search = true,
        .theme = .dark,
    });
    defer std.testing.allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "__OPENAPI_URL_JSON__") == null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Redoc.init") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "hideDownloadButton: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "disableSearch: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Internal ReDoc") != null);
}
