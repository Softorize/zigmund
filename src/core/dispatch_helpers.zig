const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub fn validationIssuesToResponse(
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

pub fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.print("{f}", .{std.json.fmt(value, .{})});
}

pub fn sendResponse(raw: *std.http.Server.Request, allocator: std.mem.Allocator, response: *const Response) !void {
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

pub fn joinPaths(allocator: std.mem.Allocator, prefix: []const u8, path: []const u8) ![]u8 {
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

pub fn isJsonContentType(content_type: []const u8) bool {
    const media_type = std.mem.trim(u8, mediaTypeToken(content_type), " \t");
    if (std.ascii.eqlIgnoreCase(media_type, "application/json")) return true;
    return std.mem.endsWith(u8, media_type, "+json");
}

pub fn mediaTypeToken(raw: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw, ';') orelse raw.len;
    return raw[0..end];
}

pub fn isWebSocketOriginAllowed(origin_header: ?[]const u8, allowed_origins: []const []const u8) bool {
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

pub fn selectWebSocketSubprotocol(
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
