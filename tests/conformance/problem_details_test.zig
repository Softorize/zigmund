const std = @import("std");
const zigmund = @import("zigmund");

// -- route that always fails with a domain error --------------------------------

const DomainErrors = error{ItemNotFound};

fn failingRoute(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    _ = allocator;
    return error.ItemNotFound;
}

// -- exception handler that returns an RFC 7807 Problem Details response --------

fn problemExceptionHandler(_: *zigmund.Request, _: anyerror, allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.problemNotFound(allocator, "The requested item was not found");
}

// -- tests ----------------------------------------------------------------------

test "exception handler returns RFC 7807 problem+json response" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "problem-details-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.addExceptionHandler(DomainErrors, problemExceptionHandler);
    try app.get("/items/42", failingRoute, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/items/42");
    defer response.deinit(std.testing.allocator);

    // HTTP status must be 404
    try std.testing.expectEqual(.not_found, response.status);

    // Content-Type must be application/problem+json
    try std.testing.expectEqualStrings("application/problem+json", response.content_type);

    // RFC 7807 required members
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"type\":\"about:blank\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"title\":\"Not Found\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"status\":404") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"detail\":\"The requested item was not found\"") != null);
}

test "problemResponse with custom type_uri and instance" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "problem-details-custom",
        .version = "0.0.1",
    });
    defer app.deinit();

    const handler = struct {
        fn handle(_: *zigmund.Request, _: anyerror, allocator: std.mem.Allocator) !zigmund.Response {
            return zigmund.problemResponse(allocator, .{
                .type_uri = "https://example.com/probs/out-of-credit",
                .title = "Out of Credit",
                .status = 403,
                .detail = "Your balance is 30, cost is 50.",
                .instance = "/account/12345/msgs/abc",
            });
        }
    }.handle;

    try app.addExceptionHandler(DomainErrors, handler);
    try app.get("/pay", failingRoute, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    var response = try client.get("/pay");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(.forbidden, response.status);
    try std.testing.expectEqualStrings("application/problem+json", response.content_type);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"type\":\"https://example.com/probs/out-of-credit\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "\"instance\":\"/account/12345/msgs/abc\"") != null);
}

test "convenience constructors set correct status codes" {
    const alloc = std.testing.allocator;

    const cases = .{
        .{ zigmund.problemBadRequest, @as(std.http.Status, .bad_request) },
        .{ zigmund.problemUnauthorized, @as(std.http.Status, .unauthorized) },
        .{ zigmund.problemForbidden, @as(std.http.Status, .forbidden) },
        .{ zigmund.problemNotFound, @as(std.http.Status, .not_found) },
        .{ zigmund.problemConflict, @as(std.http.Status, .conflict) },
        .{ zigmund.problemUnprocessableEntity, @as(std.http.Status, .unprocessable_entity) },
        .{ zigmund.problemInternalServerError, @as(std.http.Status, .internal_server_error) },
    };

    inline for (cases) |entry| {
        const func = entry[0];
        const expected_status = entry[1];

        var res = try func(alloc, "test detail");
        defer res.deinit(alloc);

        try std.testing.expectEqual(expected_status, res.status);
        try std.testing.expectEqualStrings("application/problem+json", res.content_type);
    }
}
