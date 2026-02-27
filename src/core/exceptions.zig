const std = @import("std");

pub const HTTPException = struct {
    status_code: std.http.Status,
    detail: []const u8,
    headers: []const std.http.Header = &.{},
};

pub const WebSocketException = struct {
    code: u16,
    reason: []const u8,
};
