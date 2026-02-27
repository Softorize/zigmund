const std = @import("std");

pub const SettingSpec = struct {
    key: []const u8,
    env: []const u8,
    required: bool = true,
    default_value: ?[]const u8 = null,
    allow_empty: bool = false,
};

pub const Settings = struct {
    allocator: std.mem.Allocator,
    values: std.StringHashMapUnmanaged([]u8) = .empty,
    owned_keys: std.ArrayListUnmanaged([]u8) = .empty,
    owned_values: std.ArrayListUnmanaged([]u8) = .empty,

    pub const ParseError = error{
        MissingSetting,
        InvalidBoolean,
        InvalidInteger,
    };

    pub fn deinit(self: *Settings) void {
        for (self.owned_keys.items) |key| {
            self.allocator.free(key);
        }
        self.owned_keys.deinit(self.allocator);

        for (self.owned_values.items) |value| {
            self.allocator.free(value);
        }
        self.owned_values.deinit(self.allocator);

        self.values.deinit(self.allocator);
    }

    pub fn get(self: *const Settings, key: []const u8) ?[]const u8 {
        return self.values.get(key);
    }

    pub fn require(self: *const Settings, key: []const u8) ParseError![]const u8 {
        return self.get(key) orelse error.MissingSetting;
    }

    pub fn getBool(self: *const Settings, key: []const u8) ParseError!bool {
        const raw = try self.require(key);
        if (std.ascii.eqlIgnoreCase(raw, "true") or
            std.ascii.eqlIgnoreCase(raw, "yes") or
            std.mem.eql(u8, raw, "1"))
        {
            return true;
        }
        if (std.ascii.eqlIgnoreCase(raw, "false") or
            std.ascii.eqlIgnoreCase(raw, "no") or
            std.mem.eql(u8, raw, "0"))
        {
            return false;
        }
        return error.InvalidBoolean;
    }

    pub fn getInt(self: *const Settings, comptime T: type, key: []const u8) ParseError!T {
        const raw = try self.require(key);
        return std.fmt.parseInt(T, raw, 10) catch error.InvalidInteger;
    }
};

pub const SettingsIntegration = struct {
    allocator: std.mem.Allocator,
    specs: []const SettingSpec,

    pub fn init(allocator: std.mem.Allocator, specs: []const SettingSpec) SettingsIntegration {
        return .{
            .allocator = allocator,
            .specs = specs,
        };
    }

    pub fn load(self: *const SettingsIntegration) LoadError!Settings {
        return loadSettings(self.allocator, self.specs);
    }

    pub fn loadFromEnvMap(self: *const SettingsIntegration, env_map: *const std.process.EnvMap) LoadError!Settings {
        return loadSettingsFromEnvMap(self.allocator, self.specs, env_map);
    }
};

pub const LoadError = error{
    MissingSetting,
    DuplicateSetting,
} || std.mem.Allocator.Error;

pub fn loadSettings(allocator: std.mem.Allocator, specs: []const SettingSpec) LoadError!Settings {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    return loadSettingsFromEnvMap(allocator, specs, &env_map);
}

pub fn loadSettingsFromEnvMap(
    allocator: std.mem.Allocator,
    specs: []const SettingSpec,
    env_map: *const std.process.EnvMap,
) LoadError!Settings {
    var out: Settings = .{ .allocator = allocator };
    errdefer out.deinit();

    for (specs) |spec| {
        if (out.values.contains(spec.key)) {
            return error.DuplicateSetting;
        }

        const selected = try selectValue(spec, env_map);
        if (selected == null) continue;
        const value = selected.?;

        const owned_key = try allocator.dupe(u8, spec.key);
        errdefer allocator.free(owned_key);
        const owned_value = try allocator.dupe(u8, value);
        errdefer allocator.free(owned_value);

        try out.owned_keys.append(allocator, owned_key);
        try out.owned_values.append(allocator, owned_value);
        try out.values.put(allocator, owned_key, owned_value);
    }

    return out;
}

fn selectValue(spec: SettingSpec, env_map: *const std.process.EnvMap) LoadError!?[]const u8 {
    if (env_map.get(spec.env)) |raw| {
        if (raw.len > 0 or spec.allow_empty) return raw;
        if (spec.default_value) |fallback| return fallback;
        if (spec.required) return error.MissingSetting;
        return null;
    }

    if (spec.default_value) |fallback| return fallback;
    if (spec.required) return error.MissingSetting;
    return null;
}

test "settings load with defaults and typed getters" {
    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();

    try env_map.put("APP_NAME", "zigmund");
    try env_map.put("FEATURE_X", "true");
    try env_map.put("PORT", "8080");

    const specs = [_]SettingSpec{
        .{ .key = "app_name", .env = "APP_NAME" },
        .{ .key = "feature_x", .env = "FEATURE_X" },
        .{ .key = "port", .env = "PORT" },
        .{ .key = "log_level", .env = "LOG_LEVEL", .required = false, .default_value = "info" },
    };

    var settings = try loadSettingsFromEnvMap(std.testing.allocator, &specs, &env_map);
    defer settings.deinit();

    try std.testing.expectEqualStrings("zigmund", settings.get("app_name").?);
    try std.testing.expectEqual(true, try settings.getBool("feature_x"));
    try std.testing.expectEqual(@as(u16, 8080), try settings.getInt(u16, "port"));
    try std.testing.expectEqualStrings("info", settings.get("log_level").?);
}
