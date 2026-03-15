# Bigger Applications

As your API grows, putting every route in a single file becomes unwieldy. Zigmund's `Router` lets you split routes into logical groups, each with its own prefix, tags, and dependencies, then compose them into the main application.

## Overview

A `Router` is a lightweight route collector. You create one, add routes to it, and then mount it onto the main `App` under a URL prefix using `app.includeRouter()`. Each router can have its own tags, middleware, and dependencies, keeping concerns separated.

This is the Zig equivalent of FastAPI's `APIRouter` or Express's `Router`.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn listItems(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .items = &.{
            .{ .id = 1, .name = "Portal Gun" },
            .{ .id = 2, .name = "Plumbus" },
        },
    });
}

fn readItem(
    item_id: zigmund.Path(u32, .{ .alias = "item_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .id = item_id.value.?,
        .name = "Portal Gun",
    });
}

fn listUsers(allocator: std.mem.Allocator) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .users = &.{
            .{ .id = 1, .username = "rick" },
            .{ .id = 2, .username = "morty" },
        },
    });
}

fn readUser(
    user_id: zigmund.Path(u32, .{ .alias = "user_id" }),
    allocator: std.mem.Allocator,
) !zigmund.Response {
    return zigmund.Response.json(allocator, .{
        .id = user_id.value.?,
        .username = "rick",
    });
}

pub fn main() !void {
    var app = try zigmund.App.init(.{ .port = 8080 });

    // Build an items sub-router
    var items_router = zigmund.Router.init(app.allocator);
    try items_router.addHttpRoute(.GET, "/", listItems, .{
        .summary = "List all items",
    });
    try items_router.addHttpRoute(.GET, "/{item_id}", readItem, .{
        .summary = "Read a single item",
    });

    // Build a users sub-router
    var users_router = zigmund.Router.init(app.allocator);
    try users_router.addHttpRoute(.GET, "/", listUsers, .{
        .summary = "List all users",
    });
    try users_router.addHttpRoute(.GET, "/{user_id}", readUser, .{
        .summary = "Read a single user",
    });

    // Mount sub-routers under prefixes
    try app.includeRouter("/items", &items_router, .{
        .tags = &.{"items"},
    });
    try app.includeRouter("/users", &users_router, .{
        .tags = &.{"users"},
    });

    try app.listen();
}
```

## How It Works

1. **Create a router.** `zigmund.Router.init(allocator)` creates a new, empty router.
2. **Add routes.** `addHttpRoute()` registers a route on the router, exactly like `app.get()` or `app.post()` on the main app. The path is relative to the router's eventual mount point.
3. **Mount the router.** `app.includeRouter("/items", &items_router, .{ .tags = &.{"items"} })` attaches all of the router's routes under the `/items` prefix. The router's routes become `/items/`, `/items/{item_id}`, etc.
4. **Tags propagate.** The `.tags` option on `includeRouter` applies to all routes in that router, organizing them in the OpenAPI documentation.

## Key Points

- **Prefix composition.** Route paths inside the router are relative. A route registered as `"/{item_id}"` on a router mounted at `"/items"` becomes `"/items/{item_id}"` in the final application.
- **Independent routers.** Each router is independent. You can define routers in separate files, import them, and mount them in your main application file.
- **Router-level options.** The third argument to `includeRouter()` accepts `.tags`, `.dependencies`, and other options that apply to every route in the router.
- **Nesting.** Routers can include other routers, allowing you to build deeply nested URL hierarchies.

## Recommended Project Structure

For larger applications, organize your code into modules by domain:

```
src/
  main.zig           -- App init, mount routers, listen
  routers/
    items.zig         -- Items router definition
    users.zig         -- Users router definition
  models/
    item.zig          -- Item data structures
    user.zig          -- User data structures
  deps/
    auth.zig          -- Authentication dependencies
    database.zig      -- Database session providers
```

Each router file exports a function that builds and returns a configured `Router`:

```zig
// src/routers/items.zig
pub fn createRouter(allocator: std.mem.Allocator) !zigmund.Router {
    var router = zigmund.Router.init(allocator);
    try router.addHttpRoute(.GET, "/", listItems, .{});
    try router.addHttpRoute(.GET, "/{item_id}", readItem, .{});
    return router;
}
```

Then in `main.zig`:

```zig
var items_router = try items.createRouter(app.allocator);
try app.includeRouter("/items", &items_router, .{ .tags = &.{"items"} });
```

## See Also

- [Dependencies](dependencies.md) -- Attaching shared dependencies to routers.
- [Path Operation Configuration](path-operation-configuration.md) -- Configuring summaries, tags, and metadata on routes.
- [Middleware](middleware.md) -- Adding middleware to specific router groups.
