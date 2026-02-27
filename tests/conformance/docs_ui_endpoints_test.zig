const std = @import("std");
const zigmund = @import("zigmund");

test "docs and redoc endpoints serve embedded production UI assets with config" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "Orders API",
        .version = "0.0.1",
        .openapi_url = "/schema.json",
        .docs = .{
            .title = "Orders Docs",
            .persist_authorization = true,
            .deep_linking = false,
            .display_operation_id = true,
            .doc_expansion = .none,
            .theme = .dark,
        },
        .redoc = .{
            .title = "Orders ReDoc",
            .hide_download_button = true,
            .disable_search = true,
            .theme = .dark,
        },
    });
    defer app.deinit();

    var docs_res = try app.dispatchSynthetic(.GET, "/docs", "");
    defer docs_res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, docs_res.status);
    try std.testing.expectEqualStrings("text/html; charset=utf-8", docs_res.content_type);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "SwaggerUIBundle") != null);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "persistAuthorization: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "deepLinking: false") != null);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "displayOperationId: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "docExpansion: \"none\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "\"/schema.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "Orders Docs") != null);
    try std.testing.expect(std.mem.indexOf(u8, docs_res.body, "__SWAGGER_BUNDLE_JS__") == null);

    var redoc_res = try app.dispatchSynthetic(.GET, "/redoc", "");
    defer redoc_res.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, redoc_res.status);
    try std.testing.expectEqualStrings("text/html; charset=utf-8", redoc_res.content_type);
    try std.testing.expect(std.mem.indexOf(u8, redoc_res.body, "Redoc.init") != null);
    try std.testing.expect(std.mem.indexOf(u8, redoc_res.body, "hideDownloadButton: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, redoc_res.body, "disableSearch: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, redoc_res.body, "\"/schema.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, redoc_res.body, "Orders ReDoc") != null);
    try std.testing.expect(std.mem.indexOf(u8, redoc_res.body, "__REDOC_STANDALONE_JS__") == null);
}
