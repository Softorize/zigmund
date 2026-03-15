const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "advanced/testing-dependencies/";

/// Demonstrates dependency override for testing. A production dependency
/// provides a real value; in tests, overrideDependency replaces it with
/// a mock that returns a fixed test value.

fn productionDbProvider(_: *zigmund.Request, allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    return "production-database-connection";
}

fn getDbInfo(
    db_conn: zigmund.Depends(productionDbProvider, .{ .name = "db_connection" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .db_connection = db_conn.value.?,
        .message = "Retrieved database connection via dependency injection",
    });
}

/// Example test override (used in test blocks or test harness):
///
///   fn mockDbProvider(_: *zigmund.Request, allocator: std.mem.Allocator) ![]const u8 {
///       _ = allocator;
///       return "mock-test-database";
///   }
///
///   try app.overrideDependency("db_connection", mockDbProvider);
///   var client = zigmund.TestClient.init(std.testing.allocator, &app);
///   defer client.deinit();
///   var response = try client.get("/advanced/testing-dependencies");
///   // response now contains "mock-test-database" instead of production value

pub fn buildExample(app: *zigmund.App) !void {
    try app.addDependency("db_connection", productionDbProvider);

    try app.get("/advanced/testing-dependencies", getDbInfo, .{
        .summary = "Dependency injection with test override support",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_testing_dependencies",
    });
}
