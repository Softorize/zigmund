# Zigmund

Zigmund is a FastAPI-inspired web framework bootstrap in Zig 0.15.2.

Public repository: https://github.com/Softorize/zigmund  
License: MIT ([LICENSE](LICENSE))

This repository implements the first executable slice of the long-term plan:

- Public `App` and `Router` API surface (`get/post/put/patch/delete/options/head/trace/websocket`)
- Request/response primitives
- Typed request extraction helpers (`queryAs`, `paramAs`, `bodyJson`)
- Automatic handler argument injection for marker types (`Query/Path/Header/Cookie/Body/Depends/Security`)
- Built-in HTTP runtime baseline with multi-worker serving
- Executable middleware pipeline (request + response hooks)
- Named dependency registry with per-request dependency resolution/cache
- Structured validation issue collection with 422 JSON responses
- OpenAPI 3.1 JSON generation and embedded docs pages
- OpenAPI security components and route security requirements
- Parameter marker functions (`Query`, `Path`, `Header`, `Cookie`, `Body`, `Form`, `File`, `Depends`, `Security`)
- Security scheme scaffolding (API key, HTTP auth, OAuth2)
- In-process `TestClient`
- CLI commands: `zigmund dev`, `zigmund serve`, `zigmund routes`, `zigmund openapi`, `zigmund cloud`
- Parity tooling scaffold under `tools/parity`

## Quick Start

```bash
zig build run -- serve
```

Useful commands:

```bash
zig build test
zig build parity-report
zig build parity-stubs
zig build run -- routes
zig build run -- openapi
```

## Project Layout

- `src/core/*`: app/router/lifecycle/exceptions
- `src/runtime/*`: server/websocket/proxy/config
- `src/params/*`: FastAPI-like parameter markers
- `src/deps/*`: dependency graph scaffolding
- `src/schema/*`: JSON schema scaffolding
- `src/openapi/*`: OpenAPI generator + docs HTML renderer
- `src/security/*`: auth/security helpers
- `src/integrations/*`: integration extension points
- `src/testing/*`: in-process test client
- `src/cli/*`: CLI entrypoint
- `assets/docs-ui/*`: embedded docs templates
- `examples/parity/*`: parity examples
- `tests/*`: conformance/parity/perf/interop tests
- `tools/parity/*`: parity matrix scripts

## Status

This is not full FastAPI parity yet. It is a working, compilable bootstrap that establishes the public interfaces and architecture for iterative parity delivery.
