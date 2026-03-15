const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/advanced-python-types/";

/// Zig equivalent of Python's advanced types (Union, Optional, Generic).
/// Zig uses comptime generics and tagged unions natively. This example
/// shows a comptime-parameterized response wrapper — the Zig equivalent
/// of Python's Generic[T] type annotations.

fn Envelope(comptime T: type) type {
    return struct {
        data: T,
        timestamp: i64,
        version: []const u8 = "1.0",
    };
}

const UserData = struct {
    id: u32,
    name: []const u8,
    active: bool = true,
};

fn getUser(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const envelope: Envelope(UserData) = .{
        .data = .{
            .id = 42,
            .name = "Alice",
            .active = true,
        },
        .timestamp = std.time.timestamp(),
    };

    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .data = envelope.data,
        .timestamp = envelope.timestamp,
        .version = envelope.version,
        .message = "Comptime generic Envelope(UserData) — Zig equivalent of Generic[T]",
    });
}

fn getStatus(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    // Tagged union — Zig's equivalent of Python's Union type
    const StatusValue = union(enum) {
        ok: []const u8,
        err: []const u8,
    };

    const status: StatusValue = .{ .ok = "all systems operational" };
    const label = switch (status) {
        .ok => |msg| msg,
        .err => |msg| msg,
    };

    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .status = label,
        .message = "Tagged union — Zig equivalent of Python Union types",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/advanced-python-types", getUser, .{
        .summary = "Comptime generics as Zig equivalent of Python Generic[T]",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_python_types_generic",
    });

    try app.get("/advanced/advanced-python-types/status", getStatus, .{
        .summary = "Tagged unions as Zig equivalent of Python Union types",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_python_types_union",
    });
}
