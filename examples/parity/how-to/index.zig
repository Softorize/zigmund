const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/";

/// How-to index page: provides a summary of available how-to guides
/// demonstrating common Zigmund patterns and configurations.

fn howToIndex(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .title = "How-To Guides",
        .message = "Practical guides for common Zigmund tasks",
        .guides = &[_][]const u8{
            "/how-to/general -- Common patterns: routes, params, responses",
            "/how-to/conditional-openapi -- Disable docs in production",
            "/how-to/configure-swagger-ui -- Customize Swagger UI appearance",
            "/how-to/custom-docs-ui-assets -- Configure documentation UI assets",
            "/how-to/extending-openapi -- Add x- custom OpenAPI extensions",
            "/how-to/separate-openapi-schemas -- Different request/response types",
            "/how-to/authentication-error-status-code -- Custom auth error codes",
            "/how-to/testing-database -- Database testing with SqlSessionProvider",
            "/how-to/migrate-from-pydantic-v1-to-pydantic-v2 -- Zig types vs Pydantic",
            "/how-to/graphql -- GraphQL integration",
            "/how-to/custom-request-and-route -- Custom request handling",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/index", howToIndex, .{
        .summary = "How-to guides index",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_index",
    });
}
