const std = @import("std");
const zigmund = @import("zigmund");

// -- Union variant payload structs --

const Cat = struct {
    name: []const u8,
    indoor: bool,
};

const Dog = struct {
    name: []const u8,
    breed: []const u8,
};

const Fish = struct {
    name: []const u8,
    color: []const u8 = "gold",
};

// -- Discriminated union type --

const Animal = union(enum) {
    cat: Cat,
    dog: Dog,
    fish: Fish,

    pub const zigmund_discriminator = "type";
};

// -- Handlers --

fn animalHandler(
    body: zigmund.Body(Animal, .{}),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const animal = body.value.?;
    return switch (animal) {
        .cat => |cat| zigmund.Response.json(allocator, .{
            .kind = "cat",
            .name = cat.name,
            .indoor = cat.indoor,
        }),
        .dog => |dog| zigmund.Response.json(allocator, .{
            .kind = "dog",
            .name = dog.name,
            .breed = dog.breed,
        }),
        .fish => |fish| zigmund.Response.json(allocator, .{
            .kind = "fish",
            .name = fish.name,
            .color = fish.color,
        }),
    };
}

// -- Tests --

test "discriminated union parses cat variant" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "union-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/animal", animalHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.post("/animal", "{\"type\":\"cat\",\"name\":\"Whiskers\",\"indoor\":true}");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"kind\":\"cat\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"name\":\"Whiskers\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"indoor\":true") != null);
}

test "discriminated union parses dog variant" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "union-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/animal", animalHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.post("/animal", "{\"type\":\"dog\",\"name\":\"Rex\",\"breed\":\"labrador\"}");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"kind\":\"dog\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"name\":\"Rex\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"breed\":\"labrador\"") != null);
}

test "discriminated union parses fish variant with default field" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "union-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/animal", animalHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.post("/animal", "{\"type\":\"fish\",\"name\":\"Nemo\"}");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ok, res.status);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"kind\":\"fish\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"name\":\"Nemo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.body, "\"color\":\"gold\"") != null);
}

test "unknown discriminator value returns 422" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "union-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/animal", animalHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.post("/animal", "{\"type\":\"lizard\",\"name\":\"Gecko\"}");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, res.status);
}

test "missing discriminator field returns 422" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "union-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/animal", animalHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.post("/animal", "{\"name\":\"Unknown\"}");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, res.status);
}

test "invalid json body returns 422" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "union-test",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/animal", animalHandler, .{});

    var client = zigmund.TestClient.init(std.testing.allocator, &app);

    var res = try client.post("/animal", "not json");
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(.unprocessable_entity, res.status);
}

test "openapi schema includes oneOf with discriminator for union body" {
    var app = try zigmund.App.init(std.testing.allocator, .{
        .title = "union-openapi",
        .version = "0.0.1",
    });
    defer app.deinit();

    try app.post("/animal", animalHandler, .{});

    const doc = try app.openapi();

    // Should have oneOf
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"oneOf\"") != null);
    // Should have discriminator with propertyName
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"discriminator\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"propertyName\":\"type\"") != null);
    // Should reference variant names in enum
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"cat\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"dog\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc, "\"fish\"") != null);
}
