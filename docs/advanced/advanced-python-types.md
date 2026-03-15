# Advanced Python Types

Zig equivalents of advanced Python type annotations: comptime generics for `Generic[T]`, tagged unions for `Union`, and optionals for `Optional[T]`. This page shows how Zig's type system naturally maps to Python's advanced typing features.

## Overview

Python uses `typing.Generic[T]`, `Union[A, B]`, `Optional[T]`, and other advanced type annotations to describe complex data shapes. Zig achieves the same goals through its native type system -- comptime generics, tagged unions, and optional types (`?T`). These Zig features provide stronger guarantees (compile-time checked, zero runtime overhead) while expressing the same patterns.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

/// Zig equivalent of Python's advanced types (Union, Optional, Generic).
/// Zig uses comptime generics and tagged unions natively. This example
/// shows a comptime-parameterized response wrapper — the Zig equivalent
/// of Python's Generic[T] type annotations.

fn Envelope(comptime T: type) type {
    return struct {
        data: T,
        timestamp: i64,
        version: []const u8 = "1.0",
    };
}

const UserData = struct {
    id: u32,
    name: []const u8,
    active: bool = true,
};

fn getUser(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    const envelope: Envelope(UserData) = .{
        .data = .{
            .id = 42,
            .name = "Alice",
            .active = true,
        },
        .timestamp = std.time.timestamp(),
    };

    return zigmund.Response.json(allocator, .{
        .data = envelope.data,
        .timestamp = envelope.timestamp,
        .version = envelope.version,
        .message = "Comptime generic Envelope(UserData) — Zig equivalent of Generic[T]",
    });
}

fn getStatus(_: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    // Tagged union — Zig's equivalent of Python's Union type
    const StatusValue = union(enum) {
        ok: []const u8,
        err: []const u8,
    };

    const status: StatusValue = .{ .ok = "all systems operational" };
    const label = switch (status) {
        .ok => |msg| msg,
        .err => |msg| msg,
    };

    return zigmund.Response.json(allocator, .{
        .status = label,
        .message = "Tagged union — Zig equivalent of Python Union types",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try app.get("/user", getUser, .{
        .summary = "Comptime generics as Zig equivalent of Python Generic[T]",
    });

    try app.get("/status", getStatus, .{
        .summary = "Tagged unions as Zig equivalent of Python Union types",
    });
}
```

## How It Works

### 1. Generic Types (Python `Generic[T]` -> Zig Comptime Generics)

Python uses `Generic[T]` to create parameterized types:

```python
# Python
class Envelope(Generic[T]):
    data: T
    timestamp: datetime
    version: str = "1.0"
```

Zig achieves the same with comptime functions that return types:

```zig
// Zig
fn Envelope(comptime T: type) type {
    return struct {
        data: T,
        timestamp: i64,
        version: []const u8 = "1.0",
    };
}
```

Usage is similar:

```python
# Python
envelope: Envelope[UserData] = Envelope(data=user, timestamp=now)
```

```zig
// Zig
const envelope: Envelope(UserData) = .{
    .data = user,
    .timestamp = std.time.timestamp(),
};
```

The Zig version is fully resolved at compile time -- there is no runtime type erasure.

### 2. Union Types (Python `Union[A, B]` -> Zig Tagged Unions)

Python uses `Union` to accept one of several types:

```python
# Python
StatusValue = Union[OkStatus, ErrorStatus]
```

Zig uses tagged unions:

```zig
// Zig
const StatusValue = union(enum) {
    ok: []const u8,
    err: []const u8,
};
```

Tagged unions require explicit handling of every variant via `switch`:

```zig
const label = switch (status) {
    .ok => |msg| msg,
    .err => |msg| msg,
};
```

The compiler ensures all variants are handled -- missing a case is a compile error.

### 3. Optional Types (Python `Optional[T]` -> Zig `?T`)

Python uses `Optional[T]` (or `T | None`):

```python
# Python
description: Optional[str] = None
```

Zig uses the `?` prefix:

```zig
// Zig
description: ?[]const u8 = null,
```

Access requires explicit null checking:

```zig
if (item.description) |desc| {
    // use desc
} else {
    // handle null
}
```

### 4. Type Mapping Reference

| Python Type                | Zig Equivalent                      | Notes                                    |
|---------------------------|-------------------------------------|------------------------------------------|
| `Generic[T]`             | `fn(comptime T: type) type`        | Compile-time type parameterization       |
| `Union[A, B]`            | `union(enum) { a: A, b: B }`       | Tagged union with exhaustive switch      |
| `Optional[T]`            | `?T`                                | Built-in optional type                   |
| `List[T]`                | `[]const T` or `std.ArrayList(T)`  | Slice (view) or owned dynamic array      |
| `Dict[K, V]`             | `std.StringHashMap(V)` etc.        | Hash map from std library                |
| `Tuple[A, B]`            | `struct { A, B }`                   | Anonymous or named struct                |
| `Literal["a", "b"]`      | `enum { a, b }`                     | Enum with specific variants              |
| `Any`                     | `anytype` (comptime only)           | Compile-time duck typing                 |
| `TypeVar('T')`           | `comptime T: type`                  | Compile-time type parameter              |

### 5. Advantages of Zig's Approach

- **No runtime overhead** -- all generic types are resolved at compile time (monomorphization).
- **Exhaustive switching** -- tagged unions require handling every variant; missing a case is a compile error.
- **No null pointer exceptions** -- optional types must be explicitly unwrapped.
- **No type erasure** -- generic types retain full type information.

## Key Points

- Zig comptime generics (`fn(comptime T: type) type`) replace Python's `Generic[T]` with zero runtime cost.
- Tagged unions (`union(enum)`) replace Python's `Union` with compile-time exhaustiveness checking.
- Optional types (`?T`) replace Python's `Optional[T]` with mandatory null handling.
- All type features are checked at compile time -- no runtime type errors.
- The patterns are idiomatic Zig and work seamlessly with Zigmund's serialization and OpenAPI schema generation.

## See Also

- [Dataclasses](dataclasses.md) -- Zig structs as the equivalent of Python dataclasses.
- [Response Directly](response-directly.md) -- return typed data as JSON responses.
- [Path Operation Advanced Configuration](path-operation-advanced-configuration.md) -- use typed response models in OpenAPI.
