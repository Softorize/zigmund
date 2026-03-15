const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "reference/httpconnection/";

/// Demonstrates HTTP connection handling via the Request object.
fn connectionInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    // The Request struct exposes connection-level details
    const host = req.header("host") orelse "unknown";
    const connection = req.header("connection") orelse "unknown";

    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .connection = .{
            .method = @tagName(req.method),
            .target = req.target,
            .path = req.path,
            .host = host,
            .connection_header = connection,
            .request_id = req.request_id,
        },
        .api = .{
            .raw = "req.raw - underlying std.http.Server.Request (when not synthetic)",
            .peer_address = "req.peer_address - client address",
            .target = "req.target - full request target (path + query)",
            .method = "req.method - HTTP method enum",
        },
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/reference/httpconnection", connectionInfo, .{
        .summary = "HTTP connection details from Request",
        .tags = &.{ "parity", "reference" },
        .operation_id = "ref_httpconnection_info",
    });
}
