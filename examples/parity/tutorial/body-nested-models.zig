const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "tutorial/body-nested-models/";

const Address = struct {
    street: []const u8,
    city: []const u8,
    zip_code: ?[]const u8 = null,
};

const User = struct {
    name: []const u8,
    age: u32,
    address: Address,
};

fn createUser(
    user: zigmund.Body(User, .{
        .description = "User with nested address object",
    }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    const body = user.value.?;
    return zigmund.Response.json(allocator, .{
        .name = body.name,
        .age = body.age,
        .address = .{
            .street = body.address.street,
            .city = body.address.city,
            .zip_code = body.address.zip_code,
        },
        .source = source_page,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.post("/tutorial/body-nested-models/users", createUser, .{
        .summary = "Create a user with a nested address in the JSON body",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_create_user_with_nested_model",
    });
}
