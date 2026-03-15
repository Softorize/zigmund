const std = @import("std");
const zigmund = @import("zigmund");

// ── Nested model types with zigmund_field_constraints ───────────────────────

const Address = struct {
    street: []const u8,
    city: []const u8,
    zip: []const u8,

    pub const zigmund_field_constraints = .{
        .zip = .{ .min_length = @as(?usize, 5), .max_length = @as(?usize, 10) },
        .city = .{ .min_length = @as(?usize, 1) },
    };
};

const CreateUser = struct {
    name: []const u8,
    age: u32,
    address: Address,

    pub const zigmund_field_constraints = .{
        .name = .{ .min_length = @as(?usize, 1), .max_length = @as(?usize, 100) },
        .age = .{ .gt = @as(?f64, 0), .lt = @as(?f64, 150) },
    };
};

const SimpleConstrained = struct {
    label: []const u8,
    count: i32,

    pub const zigmund_field_constraints = .{
        .label = .{ .min_length = @as(?usize, 2), .max_length = @as(?usize, 50) },
        .count = .{ .ge = @as(?f64, 0), .le = @as(?f64, 1000) },
    };
};

// ── Handlers ────────────────────────────────────────────────────────────────

fn createUserHandler(
    payload: zigmund.Body(CreateUser, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const user = payload.value orelse return error.ValidationFailed;
    return zigmund.Response.json(allocator, .{
        .name = user.name,
        .age = user.age,
        .city = user.address.city,
    });
}

fn simpleHandler(
    payload: zigmund.Body(SimpleConstrained, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const val = payload.value orelse return error.ValidationFailed;
    return zigmund.Response.json(allocator, .{
        .label = val.label,
        .count = val.count,
    });
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "nested model validation: valid input passes" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "nested-validation",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/users", createUserHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    var ok = try client.post("/users",
        \\{"name":"Alice","age":30,"address":{"street":"123 Main St","city":"Springfield","zip":"62704"}}
    );
    defer ok.deinit(std.testing.allocator);

    try std.testing.expectEqual(.ok, ok.status);
}

test "nested model validation: top-level field constraint violation returns 422" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "nested-validation",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/users", createUserHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    // name is empty string -> violates min_length=1
    var bad_name = try client.post("/users",
        \\{"name":"","age":30,"address":{"street":"123 Main St","city":"Springfield","zip":"62704"}}
    );
    defer bad_name.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unprocessable_entity, bad_name.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_name.body, "min_length") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad_name.body, "body.name") != null);
}

test "nested model validation: nested field constraint violation returns 422 with field path" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "nested-validation",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/users", createUserHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    // zip is "1234" -> violates min_length=5
    var bad_zip = try client.post("/users",
        \\{"name":"Alice","age":30,"address":{"street":"123 Main St","city":"Springfield","zip":"1234"}}
    );
    defer bad_zip.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unprocessable_entity, bad_zip.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_zip.body, "min_length") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad_zip.body, "body.address.zip") != null);
}

test "nested model validation: numeric gt constraint on top-level field" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "nested-validation",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/users", createUserHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    // age=0 -> violates gt=0
    var bad_age = try client.post("/users",
        \\{"name":"Alice","age":0,"address":{"street":"123 Main St","city":"Springfield","zip":"62704"}}
    );
    defer bad_age.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unprocessable_entity, bad_age.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_age.body, "\"type\":\"gt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad_age.body, "body.age") != null);
}

test "nested model validation: nested city empty violates min_length" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "nested-validation",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/users", createUserHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    // city is empty -> violates min_length=1
    var bad_city = try client.post("/users",
        \\{"name":"Alice","age":30,"address":{"street":"123 Main St","city":"","zip":"62704"}}
    );
    defer bad_city.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unprocessable_entity, bad_city.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_city.body, "min_length") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad_city.body, "body.address.city") != null);
}

test "nested model validation: simple struct with ge/le constraints" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "nested-validation",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/items", simpleHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    // Valid input
    var ok = try client.post("/items",
        \\{"label":"test","count":50}
    );
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, ok.status);

    // count = -1 violates ge=0
    var bad_count = try client.post("/items",
        \\{"label":"test","count":-1}
    );
    defer bad_count.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, bad_count.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_count.body, "\"type\":\"ge\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad_count.body, "body.count") != null);
}

test "nested model validation: max_length on nested zip" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "nested-validation",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/users", createUserHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);
    defer client.deinit();

    // zip is too long -> violates max_length=10
    var bad_zip = try client.post("/users",
        \\{"name":"Alice","age":30,"address":{"street":"123 Main St","city":"Springfield","zip":"12345678901"}}
    );
    defer bad_zip.deinit(std.testing.allocator);

    try std.testing.expectEqual(.unprocessable_entity, bad_zip.status);
    try std.testing.expect(std.mem.indexOf(u8, bad_zip.body, "max_length") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad_zip.body, "body.address.zip") != null);
}
