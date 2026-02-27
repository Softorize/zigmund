const std = @import("std");
const zigmund = @import("zigmund");

fn readSettings(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();

    try env_map.put("APP_NAME", "zigmund");
    try env_map.put("FEATURE_BETA", "true");
    try env_map.put("PORT", "9001");

    const specs = [_]zigmund.SettingSpec{
        .{ .key = "app_name", .env = "APP_NAME" },
        .{ .key = "feature_beta", .env = "FEATURE_BETA" },
        .{ .key = "port", .env = "PORT" },
        .{ .key = "environment", .env = "ENVIRONMENT", .required = false, .default_value = "dev" },
    };

    var settings = try zigmund.loadSettingsFromEnvMap(allocator, &specs, &env_map);
    defer settings.deinit();

    return zigmund.Response.json(allocator, .{
        .app_name = settings.get("app_name").?,
        .feature_beta = try settings.getBool("feature_beta"),
        .port = try settings.getInt(u16, "port"),
        .environment = settings.get("environment").?,
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/advanced/settings", readSettings, .{
        .summary = "Load typed settings from environment",
        .tags = &.{ "parity", "advanced" },
        .operation_id = "advanced_settings_read",
    });
}
