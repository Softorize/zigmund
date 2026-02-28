const std = @import("std");

pub const Response = struct {
    pub const CookieSameSite = enum {
        lax,
        strict,
        none,

        fn asHeaderValue(self: CookieSameSite) []const u8 {
            return switch (self) {
                .lax => "Lax",
                .strict => "Strict",
                .none => "None",
            };
        }
    };

    pub const CookieOptions = struct {
        path: ?[]const u8 = "/",
        domain: ?[]const u8 = null,
        max_age_seconds: ?i64 = null,
        expires: ?[]const u8 = null,
        secure: bool = false,
        http_only: bool = true,
        same_site: ?CookieSameSite = null,
    };

    pub const ServerSentEvent = struct {
        data: []const u8,
        id: ?[]const u8 = null,
        event: ?[]const u8 = null,
        retry_ms: ?u32 = null,
    };

    status: std.http.Status = .ok,
    body: []const u8 = "",
    content_type: []const u8 = "text/plain; charset=utf-8",
    headers: std.ArrayListUnmanaged(std.http.Header) = .empty,
    owned_body: ?[]u8 = null,

    pub fn text(body: []const u8) Response {
        return .{
            .status = .ok,
            .body = body,
            .content_type = "text/plain; charset=utf-8",
        };
    }

    pub fn html(body: []const u8) Response {
        return .{
            .status = .ok,
            .body = body,
            .content_type = "text/html; charset=utf-8",
        };
    }

    pub fn json(allocator: std.mem.Allocator, value: anytype) !Response {
        const payload = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{})});
        return .{
            .status = .ok,
            .body = payload,
            .content_type = "application/json",
            .owned_body = payload,
        };
    }

    pub fn notModified() Response {
        return Response.text("").withStatus(.not_modified);
    }

    pub fn redirect(allocator: std.mem.Allocator, location: []const u8, status: std.http.Status) !Response {
        var response = Response.text("").withStatus(status);
        try response.setHeader(allocator, "location", location);
        return response;
    }

    pub fn fileFromPath(allocator: std.mem.Allocator, path: []const u8) !Response {
        const payload = try std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024 * 1024);
        return .{
            .status = .ok,
            .body = payload,
            .content_type = guessContentType(path),
            .owned_body = payload,
        };
    }

    pub fn streamChunks(
        allocator: std.mem.Allocator,
        chunks: []const []const u8,
        content_type: []const u8,
    ) !Response {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        for (chunks) |chunk| {
            try out.appendSlice(allocator, chunk);
        }

        const payload = try out.toOwnedSlice(allocator);
        return .{
            .status = .ok,
            .body = payload,
            .content_type = content_type,
            .owned_body = payload,
        };
    }

    pub fn eventStream(
        allocator: std.mem.Allocator,
        events: []const ServerSentEvent,
    ) !Response {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        var writer = out.writer(allocator);
        for (events) |event| {
            if (event.id) |value| try writer.print("id: {s}\n", .{value});
            if (event.event) |value| try writer.print("event: {s}\n", .{value});
            if (event.retry_ms) |value| try writer.print("retry: {d}\n", .{value});
            try writeSseDataLines(&writer, event.data);
            try writer.writeByte('\n');
        }

        const payload = try out.toOwnedSlice(allocator);
        var response = Response{
            .status = .ok,
            .body = payload,
            .content_type = "text/event-stream; charset=utf-8",
            .owned_body = payload,
        };
        errdefer response.deinit(allocator);
        try response.setHeader(allocator, "cache-control", "no-cache");
        try response.setHeader(allocator, "connection", "keep-alive");
        return response;
    }

    pub fn withStatus(self: Response, status: std.http.Status) Response {
        var next = self;
        next.status = status;
        return next;
    }

    pub fn setHeader(self: *Response, allocator: std.mem.Allocator, name: []const u8, value: []const u8) !void {
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);
        const owned_value = try allocator.dupe(u8, value);
        errdefer allocator.free(owned_value);

        try self.headers.append(allocator, .{
            .name = owned_name,
            .value = owned_value,
        });
    }

    pub fn setCookie(
        self: *Response,
        allocator: std.mem.Allocator,
        name: []const u8,
        value: []const u8,
        opts: CookieOptions,
    ) !void {
        var builder: std.ArrayList(u8) = .empty;
        defer builder.deinit(allocator);

        var writer = builder.writer(allocator);
        try writer.print("{s}={s}", .{ name, value });

        if (opts.path) |path| try writer.print("; Path={s}", .{path});
        if (opts.domain) |domain| try writer.print("; Domain={s}", .{domain});
        if (opts.max_age_seconds) |max_age| try writer.print("; Max-Age={d}", .{max_age});
        if (opts.expires) |expires| try writer.print("; Expires={s}", .{expires});
        if (opts.secure) try writer.writeAll("; Secure");
        if (opts.http_only) try writer.writeAll("; HttpOnly");
        if (opts.same_site) |same_site| try writer.print("; SameSite={s}", .{same_site.asHeaderValue()});

        const header_value = try builder.toOwnedSlice(allocator);
        defer allocator.free(header_value);

        try self.setHeader(allocator, "set-cookie", header_value);
    }

    pub fn deleteCookie(
        self: *Response,
        allocator: std.mem.Allocator,
        name: []const u8,
        opts: CookieOptions,
    ) !void {
        var delete_opts = opts;
        delete_opts.max_age_seconds = 0;
        delete_opts.expires = "Thu, 01 Jan 1970 00:00:00 GMT";
        try self.setCookie(allocator, name, "", delete_opts);
    }

    pub fn setEtag(self: *Response, allocator: std.mem.Allocator, etag: []const u8) !void {
        try self.setHeader(allocator, "etag", etag);
    }

    pub fn setLastModified(self: *Response, allocator: std.mem.Allocator, value: []const u8) !void {
        try self.setHeader(allocator, "last-modified", value);
    }

    pub fn conditionalNotModified(
        allocator: std.mem.Allocator,
        etag: ?[]const u8,
        last_modified: ?[]const u8,
        if_none_match: ?[]const u8,
        if_modified_since: ?[]const u8,
    ) !?Response {
        if (etag) |etag_value| {
            if (if_none_match) |if_none_match_value| {
                if (std.mem.eql(u8, std.mem.trim(u8, if_none_match_value, " \t"), etag_value)) {
                    var response = Response.notModified();
                    try response.setEtag(allocator, etag_value);
                    if (last_modified) |lm| try response.setLastModified(allocator, lm);
                    return response;
                }
            }
        }

        if (last_modified) |last_modified_value| {
            if (if_modified_since) |if_modified_since_value| {
                if (std.mem.eql(u8, std.mem.trim(u8, if_modified_since_value, " \t"), last_modified_value)) {
                    var response = Response.notModified();
                    if (etag) |etag_value| try response.setEtag(allocator, etag_value);
                    try response.setLastModified(allocator, last_modified_value);
                    return response;
                }
            }
        }

        return null;
    }

    pub fn header(self: *const Response, name: []const u8) ?[]const u8 {
        for (self.headers.items) |hdr| {
            if (std.ascii.eqlIgnoreCase(hdr.name, name)) {
                return hdr.value;
            }
        }
        return null;
    }

    pub fn hasHeader(self: *const Response, name: []const u8) bool {
        return self.header(name) != null;
    }

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        if (self.owned_body) |buf| {
            allocator.free(buf);
            self.owned_body = null;
        }
        for (self.headers.items) |hdr| {
            allocator.free(hdr.name);
            allocator.free(hdr.value);
        }
        self.headers.deinit(allocator);
    }
};

fn guessContentType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".txt")) return "text/plain; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) return "image/jpeg";
    return "application/octet-stream";
}

fn writeSseDataLines(writer: anytype, data: []const u8) !void {
    var start: usize = 0;
    while (start < data.len) {
        const rel_end = std.mem.indexOfScalar(u8, data[start..], '\n');
        const end = if (rel_end) |offset| start + offset else data.len;
        try writer.print("data: {s}\n", .{data[start..end]});
        if (end == data.len) break;
        start = end + 1;
    }
    if (data.len == 0) {
        try writer.writeAll("data:\n");
    }
}

test "json response" {
    var res = try Response.json(std.testing.allocator, .{ .ok = true });
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("application/json", res.content_type);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"ok\":true") != null);
}

test "redirect and cookies" {
    var res = try Response.redirect(std.testing.allocator, "/login", .temporary_redirect);
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("/login", res.header("location").?);

    try res.setCookie(std.testing.allocator, "session", "abc", .{
        .secure = true,
        .same_site = .lax,
    });
    try std.testing.expect(res.header("set-cookie") != null);

    try res.deleteCookie(std.testing.allocator, "session", .{});
    try std.testing.expect(res.header("set-cookie") != null);
}

test "chunk streaming concatenates payload" {
    var res = try Response.streamChunks(
        std.testing.allocator,
        &.{ "hel", "lo", " ", "world" },
        "text/plain; charset=utf-8",
    );
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("hello world", res.body);
}

test "event stream response formats events and headers" {
    const events = [_]Response.ServerSentEvent{
        .{
            .id = "evt-1",
            .event = "message",
            .retry_ms = 1500,
            .data = "hello\nworld",
        },
        .{
            .data = "",
        },
    };

    var res = try Response.eventStream(std.testing.allocator, &events);
    defer res.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("text/event-stream; charset=utf-8", res.content_type);
    try std.testing.expectEqualStrings("no-cache", res.header("cache-control").?);
    try std.testing.expectEqualStrings("keep-alive", res.header("connection").?);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "id: evt-1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "event: message\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "retry: 1500\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "data: hello\ndata: world\n\n") != null);
}

test "conditionalNotModified returns 304 with cache validators" {
    var by_etag = (try Response.conditionalNotModified(
        std.testing.allocator,
        "\"v1\"",
        "Mon, 11 Mar 2024 10:00:00 GMT",
        "\"v1\"",
        null,
    )).?;
    defer by_etag.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_modified, by_etag.status);
    try std.testing.expectEqualStrings("\"v1\"", by_etag.header("etag").?);

    var by_last_modified = (try Response.conditionalNotModified(
        std.testing.allocator,
        "\"v2\"",
        "Tue, 12 Mar 2024 10:00:00 GMT",
        null,
        "Tue, 12 Mar 2024 10:00:00 GMT",
    )).?;
    defer by_last_modified.deinit(std.testing.allocator);
    try std.testing.expectEqual(.not_modified, by_last_modified.status);
    try std.testing.expectEqualStrings("Tue, 12 Mar 2024 10:00:00 GMT", by_last_modified.header("last-modified").?);

    try std.testing.expect((try Response.conditionalNotModified(
        std.testing.allocator,
        "\"v3\"",
        "Wed, 13 Mar 2024 10:00:00 GMT",
        "\"other\"",
        "Wed, 12 Mar 2024 10:00:00 GMT",
    )) == null);
}
