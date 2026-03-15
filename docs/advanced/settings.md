# Settings

Load typed application settings from environment variables using Zigmund's settings infrastructure. Define a schema of expected settings, load them from the environment, and access them with type-safe getters.

## Overview

Application configuration should be externalized from code. Zigmund provides `SettingSpec` to define expected environment variables, `loadSettingsFromEnvMap` to load and validate them, and typed accessors like `getBool()` and `getInt()` to retrieve values with automatic type conversion.

This is the Zig equivalent of FastAPI/Pydantic's `BaseSettings` pattern for environment-based configuration.

## Example

```zig
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
    try app.get("/settings", readSettings, .{
        .summary = "Load typed settings from environment",
    });
}
```

## How It Works

### 1. Defining Setting Specifications

Create an array of `SettingSpec` structs that describe each expected setting:

```zig
const specs = [_]zigmund.SettingSpec{
    .{ .key = "app_name", .env = "APP_NAME" },
    .{ .key = "port", .env = "PORT" },
    .{ .key = "environment", .env = "ENVIRONMENT", .required = false, .default_value = "dev" },
};
```

Each `SettingSpec` has the following fields:

| Field           | Type           | Description                                        |
|-----------------|----------------|----------------------------------------------------|
| `key`           | `[]const u8`   | Internal key used to retrieve the setting.         |
| `env`           | `[]const u8`   | Environment variable name to read from.            |
| `required`      | `bool`         | Whether the variable must be set. Default: `true`. |
| `default_value` | `?[]const u8`  | Fallback value when the variable is not set.       |

### 2. Loading Settings

Load settings from an environment map:

```zig
var settings = try zigmund.loadSettingsFromEnvMap(allocator, &specs, &env_map);
defer settings.deinit();
```

In production, the environment map comes from `std.process.getEnvMap()` or similar. The example uses a manually constructed `EnvMap` for demonstration.

If a required setting is missing and has no `default_value`, `loadSettingsFromEnvMap` returns an error.

### 3. Accessing Settings as Strings

Use `settings.get(key)` to retrieve a setting as an optional string:

```zig
const app_name = settings.get("app_name").?;
```

### 4. Typed Accessors

Convert settings to specific types with typed getters:

```zig
const port = try settings.getInt(u16, "port");         // Parse as u16
const beta = try settings.getBool("feature_beta");       // Parse as bool
```

These return an error if the value cannot be parsed as the requested type.

### 5. Optional Settings with Defaults

Mark a setting as optional with `.required = false` and provide a `.default_value`:

```zig
.{ .key = "environment", .env = "ENVIRONMENT", .required = false, .default_value = "dev" },
```

If `ENVIRONMENT` is not set, `settings.get("environment")` returns `"dev"`.

## Key Points

- `SettingSpec` defines a schema for environment-based configuration.
- `loadSettingsFromEnvMap` validates required settings and applies defaults.
- Use `settings.get()` for string values, `settings.getInt()` for integers, and `settings.getBool()` for booleans.
- Required settings without defaults cause an error if the environment variable is not set.
- Always call `defer settings.deinit()` to release allocated memory.
- Load settings in a startup hook or at application initialization for early validation.

## See Also

- [Events](events.md) -- load settings in a startup hook.
- [Behind a Proxy](behind-a-proxy.md) -- configure proxy settings from environment variables.
- [Advanced Dependencies](advanced-dependencies.md) -- inject settings as dependencies.
