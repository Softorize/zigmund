const std = @import("std");
const zigmund = @import("zigmund");

const source_page = "how-to/migrate-from-pydantic-v1-to-pydantic-v2/";

/// This page is not applicable to Zigmund. In Python's FastAPI, Pydantic
/// provides runtime data validation and serialization. In Zigmund, Zig's
/// native type system serves this role: structs define models with
/// compile-time type checking, and the framework handles JSON
/// serialization/deserialization automatically.

const UserModel = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    is_active: bool = true,
};

fn migrationInfo(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .message = "Pydantic migration is not applicable to Zigmund",
        .explanation = "Zigmund uses Zig's native type system instead of Pydantic. " ++
            "Structs serve as data models with compile-time validation. " ++
            "No migration needed -- define Zig structs and the framework handles the rest.",
        .zig_equivalents = .{
            .pydantic_basemodel = "Zig struct definition",
            .field_validation = "Compile-time type checking + RouteOptions constraints",
            .json_serialization = "Automatic via std.json / zigmund.Response.json",
            .optional_fields = "?T (Zig optional type)",
            .default_values = "Struct field defaults (e.g., is_active: bool = true)",
        },
    });
}

fn exampleModel(allocator: std.mem.Allocator) !zigmund.Response {
    const user = UserModel{
        .id = 1,
        .name = "Alice",
        .email = "alice@example.com",
        .is_active = true,
    };
    return zigmund.Response.json(allocator, .{
        .page = source_page,
        .model = "UserModel",
        .user = .{
            .id = user.id,
            .name = user.name,
            .email = user.email,
            .is_active = user.is_active,
        },
        .note = "Zig structs replace Pydantic models with zero runtime overhead",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/how-to/migrate-from-pydantic-v1-to-pydantic-v2", migrationInfo, .{
        .summary = "Pydantic migration N/A -- Zigmund uses Zig types directly",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_pydantic_migration_info",
    });

    try app.get("/how-to/migrate-from-pydantic-v1-to-pydantic-v2/example", exampleModel, .{
        .summary = "Zig struct as model replacement for Pydantic",
        .tags = &.{ "parity", "how-to" },
        .operation_id = "howto_pydantic_migration_example",
        .response_model = UserModel,
    });
}
