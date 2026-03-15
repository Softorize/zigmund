const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub fn serializeValue(req: *const Request, allocator: std.mem.Allocator, value: anytype) !Response {
    const route_status = routeStatusCode(req);
    const response_class = req.dependency("zigmund.route.default_response_class");
    return serializeValueWithClass(allocator, response_class, route_status, value);
}

pub fn routeStatusCode(req: *const Request) std.http.Status {
    const raw = req.dependency("zigmund.route.status_code") orelse return .ok;
    const code = std.fmt.parseInt(u16, raw, 10) catch return .ok;
    return @enumFromInt(code);
}

fn serializeValueWithClass(
    allocator: std.mem.Allocator,
    response_class: ?[]const u8,
    route_status: std.http.Status,
    value: anytype,
) !Response {
    const T = @TypeOf(value);

    if (comptime T == Response.RedirectPayload) {
        return redirectFromPayload(allocator, value, route_status);
    }
    if (comptime T == Response.FilePayload) {
        return fileFromPayload(allocator, value, route_status);
    }
    if (comptime T == Response.StreamPayload) {
        return streamFromPayload(allocator, value, route_status);
    }
    if (comptime T == Response.EventStreamPayload) {
        return eventStreamFromPayload(allocator, value, route_status);
    }

    if (classNameEq(response_class, "PlainTextResponse")) {
        return textResponse(allocator, value, "text/plain; charset=utf-8", route_status);
    }
    if (classNameEq(response_class, "HTMLResponse")) {
        return textResponse(allocator, value, "text/html; charset=utf-8", route_status);
    }
    if (classNameEq(response_class, "RedirectResponse")) {
        return redirectFromValue(allocator, value, route_status);
    }
    if (classNameEq(response_class, "FileResponse")) {
        return fileFromValue(allocator, value, route_status);
    }
    if (classNameEq(response_class, "StreamingResponse")) {
        return streamFromValue(allocator, value, route_status);
    }
    if (classNameEq(response_class, "EventSourceResponse")) {
        return eventStreamFromValue(allocator, value, route_status);
    }

    var response = try Response.json(allocator, value);
    response.status = route_status;
    return response;
}

fn classNameEq(class_name: ?[]const u8, expected: []const u8) bool {
    return std.ascii.eqlIgnoreCase(class_name orelse return false, expected);
}

fn applyStatus(response: Response, status: std.http.Status) Response {
    var out = response;
    out.status = status;
    return out;
}

fn effectiveRedirectStatus(route_status: std.http.Status, fallback: std.http.Status) std.http.Status {
    return if (route_status == .ok) fallback else route_status;
}

fn textResponse(
    allocator: std.mem.Allocator,
    value: anytype,
    content_type: []const u8,
    route_status: std.http.Status,
) !Response {
    const payload = try textBodyFromValue(allocator, value);
    return .{
        .status = route_status,
        .body = payload,
        .content_type = content_type,
        .owned_body = payload,
    };
}

fn textBodyFromValue(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .optional => if (value) |inner|
            textBodyFromValue(allocator, inner)
        else
            allocator.dupe(u8, ""),
        .bool, .int, .comptime_int, .float, .comptime_float => std.fmt.allocPrint(allocator, "{}", .{value}),
        .@"enum" => allocator.dupe(u8, @tagName(value)),
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8) break :blk allocator.dupe(u8, value);
            break :blk error.UnsupportedResponsePayload;
        },
        else => error.UnsupportedResponsePayload,
    };
}

fn redirectFromValue(
    allocator: std.mem.Allocator,
    value: anytype,
    route_status: std.http.Status,
) !Response {
    const T = @TypeOf(value);
    if (comptime isByteSliceType(T)) {
        return Response.redirect(allocator, value, effectiveRedirectStatus(route_status, .temporary_redirect));
    }
    return error.UnsupportedResponsePayload;
}

fn redirectFromPayload(
    allocator: std.mem.Allocator,
    payload: Response.RedirectPayload,
    route_status: std.http.Status,
) !Response {
    const status = if (route_status != .ok and payload.status_code == .temporary_redirect)
        route_status
    else
        payload.status_code;
    return Response.redirect(allocator, payload.location, status);
}

fn fileFromValue(
    allocator: std.mem.Allocator,
    value: anytype,
    route_status: std.http.Status,
) !Response {
    const T = @TypeOf(value);
    if (comptime isByteSliceType(T)) {
        var response = try Response.fileFromPath(allocator, value);
        if (route_status != .ok) response.status = route_status;
        return response;
    }
    return error.UnsupportedResponsePayload;
}

fn fileFromPayload(
    allocator: std.mem.Allocator,
    payload: Response.FilePayload,
    route_status: std.http.Status,
) !Response {
    var response = try Response.fileFromPathWithContentType(allocator, payload.path, payload.content_type);
    if (route_status != .ok) response.status = route_status;
    return response;
}

fn streamFromValue(
    allocator: std.mem.Allocator,
    value: anytype,
    route_status: std.http.Status,
) !Response {
    const T = @TypeOf(value);
    if (comptime isChunkSliceType(T)) {
        return applyStatus(
            try Response.streamChunks(allocator, value, Response.contentTypeForClassName("StreamingResponse")),
            route_status,
        );
    }
    return error.UnsupportedResponsePayload;
}

fn streamFromPayload(
    allocator: std.mem.Allocator,
    payload: Response.StreamPayload,
    route_status: std.http.Status,
) !Response {
    return applyStatus(
        try Response.streamChunks(allocator, payload.chunks, payload.content_type),
        route_status,
    );
}

fn eventStreamFromValue(
    allocator: std.mem.Allocator,
    value: anytype,
    route_status: std.http.Status,
) !Response {
    const T = @TypeOf(value);
    if (comptime isSseSliceType(T)) {
        return applyStatus(try Response.eventStream(allocator, value), route_status);
    }
    return error.UnsupportedResponsePayload;
}

fn eventStreamFromPayload(
    allocator: std.mem.Allocator,
    payload: Response.EventStreamPayload,
    route_status: std.http.Status,
) !Response {
    return applyStatus(try Response.eventStream(allocator, payload.events), route_status);
}

fn isByteSliceType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.size == .slice and ptr.child == u8,
        else => false,
    };
}

fn isChunkSliceType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.size == .slice and isByteSliceType(ptr.child),
        else => false,
    };
}

fn isSseSliceType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.size == .slice and ptr.child == Response.ServerSentEvent,
        else => false,
    };
}
