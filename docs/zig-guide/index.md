# Zig Guide

This section is for developers coming to Zigmund from Python (FastAPI/Flask/Django), TypeScript (Express/Fastify), Go, or other languages. It explains how Zig's unique features map to the patterns you already know, and how Zigmund leverages them.

If you are already comfortable with Zig, you can skip directly to the [Tutorial](../tutorial/index.md).

---

## Topics

- [Comptime and Type Reflection](comptime.md) -- How Zigmund uses Zig's compile-time execution to provide automatic parameter injection, OpenAPI schema generation, and type-safe routing without runtime reflection or code generation. Covers `comptime`, `@typeInfo`, and how they replace Python decorators and TypeScript generics.

- [Error Handling](error-handling.md) -- Zig's error union system (`!T`), `try`, `catch`, and error sets. How Zigmund handlers return `!zigmund.Response` and how errors propagate through the middleware stack. Comparison with Python exceptions and Go's `error` return pattern.

- [Memory Management](memory-management.md) -- Zig's allocator-based memory model: `GeneralPurposeAllocator`, arena allocators, and per-request allocation. How Zigmund manages memory for request parsing, response building, and dependency lifetimes. No garbage collector -- what that means for your code.

- [Structs and Type System](structs-and-types.md) -- Zig structs as the equivalent of Python dataclasses, Pydantic models, and TypeScript interfaces. Optional fields, default values, anonymous struct literals, and how Zigmund uses struct types for request body parsing, query parameter models, and response shaping.
