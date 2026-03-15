const std = @import("std");
const App = @import("../core/app.zig").App;
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

/// Supported content types for negotiation.
pub const ContentType = enum {
    json,
    plain_text,
    html,
    xml,
    any,

    /// Return the canonical MIME type string for the content type.
    pub fn mimeType(self: ContentType) []const u8 {
        return switch (self) {
            .json => "application/json",
            .plain_text => "text/plain",
            .html => "text/html",
            .xml => "application/xml",
            .any => "*/*",
        };
    }

    /// Return a short tag name (stored in the dependency value).
    pub fn tagName(self: ContentType) []const u8 {
        return switch (self) {
            .json => "json",
            .plain_text => "plain_text",
            .html => "html",
            .xml => "xml",
            .any => "any",
        };
    }

    /// Parse a tag name back to a ContentType.
    pub fn fromTagName(name: []const u8) ?ContentType {
        if (std.mem.eql(u8, name, "json")) return .json;
        if (std.mem.eql(u8, name, "plain_text")) return .plain_text;
        if (std.mem.eql(u8, name, "html")) return .html;
        if (std.mem.eql(u8, name, "xml")) return .xml;
        if (std.mem.eql(u8, name, "any")) return .any;
        return null;
    }
};

pub const ContentNegotiationConfig = struct {
    default: ContentType = .json,
    supported: []const ContentType = &.{ .json, .plain_text, .html },
};

/// Parse an Accept header value and determine the preferred content type
/// from the set of supported types in the config.
///
/// Performs simple substring matching against known MIME types, selecting
/// the first supported match found in the Accept header. Falls back to
/// `config.default` when no match is found or when the header contains
/// the wildcard `*/*`.
pub fn negotiateContentType(accept_header: ?[]const u8, config: ContentNegotiationConfig) ContentType {
    const accept = accept_header orelse return config.default;

    // Check if accept is just a wildcard
    if (std.mem.indexOf(u8, accept, "*/*") != null) {
        // Wildcard — check if there's a more specific type first
        // Only return default if there's nothing more specific
        var has_specific = false;
        for (config.supported) |ct| {
            if (ct == .any) continue;
            if (containsMimeType(accept, ct)) {
                return ct;
            }
            _ = &has_specific;
        }
        return config.default;
    }

    // Try each supported type in order
    for (config.supported) |ct| {
        if (ct == .any) continue;
        if (containsMimeType(accept, ct)) {
            return ct;
        }
    }

    return config.default;
}

fn containsMimeType(accept: []const u8, ct: ContentType) bool {
    return switch (ct) {
        .json => std.mem.indexOf(u8, accept, "application/json") != null,
        .plain_text => std.mem.indexOf(u8, accept, "text/plain") != null,
        .html => std.mem.indexOf(u8, accept, "text/html") != null,
        .xml => (std.mem.indexOf(u8, accept, "application/xml") != null or
            std.mem.indexOf(u8, accept, "text/xml") != null),
        .any => std.mem.indexOf(u8, accept, "*/*") != null,
    };
}

/// The dependency key used to store the negotiated content type on the request.
pub const dependency_key = "_content_type";

var global_config: ContentNegotiationConfig = .{};

/// Request hook: parse Accept header and store negotiated content type.
fn requestHook(req: *Request, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const accept = req.header("accept");
    const ct = negotiateContentType(accept, global_config);
    try req.setDependencyValue(dependency_key, ct.tagName());
}

/// Create a Middleware struct ready to register with the app.
pub fn middleware(config: ContentNegotiationConfig) App.Middleware {
    global_config = config;
    return .{
        .name = "content_negotiation",
        .request_hook = &requestHook,
    };
}

// ── Tests ───────────────────────────────────────────────────────────────

test "negotiate json from Accept header" {
    const ct = negotiateContentType("application/json", .{});
    try std.testing.expectEqual(ContentType.json, ct);
}

test "negotiate html from Accept header" {
    const ct = negotiateContentType("text/html", .{
        .supported = &.{ .json, .plain_text, .html },
    });
    try std.testing.expectEqual(ContentType.html, ct);
}

test "negotiate plain text from Accept header" {
    const ct = negotiateContentType("text/plain", .{
        .supported = &.{ .json, .plain_text, .html },
    });
    try std.testing.expectEqual(ContentType.plain_text, ct);
}

test "negotiate xml from Accept header" {
    const ct = negotiateContentType("application/xml", .{
        .supported = &.{ .json, .xml },
    });
    try std.testing.expectEqual(ContentType.xml, ct);
}

test "negotiate text/xml from Accept header" {
    const ct = negotiateContentType("text/xml", .{
        .supported = &.{ .json, .xml },
    });
    try std.testing.expectEqual(ContentType.xml, ct);
}

test "wildcard returns default" {
    const ct = negotiateContentType("*/*", .{
        .default = .json,
    });
    try std.testing.expectEqual(ContentType.json, ct);
}

test "no Accept header returns default" {
    const ct = negotiateContentType(null, .{
        .default = .plain_text,
    });
    try std.testing.expectEqual(ContentType.plain_text, ct);
}

test "unsupported type returns default" {
    const ct = negotiateContentType("image/png", .{
        .default = .json,
        .supported = &.{ .json, .html },
    });
    try std.testing.expectEqual(ContentType.json, ct);
}

test "multiple types in Accept header picks first supported" {
    const ct = negotiateContentType("text/html, application/json;q=0.9", .{
        .supported = &.{ .json, .html },
    });
    // html appears first in the Accept header AND is first-matched in supported order
    // since we iterate supported in order and html is at index 1, but json is at index 0
    // however json doesn't match "text/html" — it matches "application/json"
    // so we check .json first: "application/json" is in the accept string, so json matches first
    try std.testing.expectEqual(ContentType.json, ct);
}

test "ContentType mimeType returns correct strings" {
    try std.testing.expectEqualStrings("application/json", ContentType.json.mimeType());
    try std.testing.expectEqualStrings("text/plain", ContentType.plain_text.mimeType());
    try std.testing.expectEqualStrings("text/html", ContentType.html.mimeType());
    try std.testing.expectEqualStrings("application/xml", ContentType.xml.mimeType());
    try std.testing.expectEqualStrings("*/*", ContentType.any.mimeType());
}

test "ContentType roundtrip through tagName" {
    const types = [_]ContentType{ .json, .plain_text, .html, .xml, .any };
    for (types) |ct| {
        const tag = ct.tagName();
        const parsed = ContentType.fromTagName(tag);
        try std.testing.expectEqual(ct, parsed.?);
    }
}
