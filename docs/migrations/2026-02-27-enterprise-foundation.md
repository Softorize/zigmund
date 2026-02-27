# 2026-02-27 Enterprise Foundation

## Breaking/Behavioral Changes

1. Parity coverage gates now enforce full matrix completion (`stub=0`, `missing=0`) against the pinned FastAPI docs baseline.
2. Performance regression checks now run in two modes:
   - `shared`: relaxed thresholds for shared CI runners.
   - `strict`: enterprise thresholds for dedicated benchmark environments.
3. `zigmund cloud` now supports provider-aware planning (`--provider`) and scaffold emission (`--emit-dir`) for deployment files.
4. Release-channel automation has been introduced (`nightly|alpha|beta|rc|stable`) with channel-aware release metadata.
5. Additive API extensions:
   - `AppConfig.request_id_enabled` to disable request-id generation/propagation when desired.
   - `SecurityOptional(...)` and `SecurityNamedOptional(...)` for optional auth marker behavior (best-effort auth without scope requirements).
   - `DependsOptions.cleanup` for request-scoped provider cleanup hooks on `Depends(...)` markers.
6. Dependency injection runtime behavior:
   - unnamed provider markers now use callable-identity cache keys, so `Depends(provider, .{})` with `use_cache=true` caches once per request without requiring explicit `name`.
7. Validation behavior:
   - marker `pattern` constraints now evaluate full regex expressions (POSIX ERE), not only literal prefix/suffix/contains matching.
8. WebSocket handler API extension:
   - request-aware handlers are now supported via `fn(*websocket.Connection, *Request, std.mem.Allocator) !void` while preserving compatibility with legacy `fn(*websocket.Connection, std.mem.Allocator) !void`.
9. WebSocket marker injection behavior:
   - websocket handlers now support FastAPI-style marker injection (`Path/Query/Header/Cookie/Depends/Security`) via injector binding.
   - registered injected websocket dependencies are now executed during handshake dependency checks (pre-upgrade), matching HTTP dependency pre-execution semantics.
10. OpenAPI websocket metadata:
   - `x-zigmund-websocket` operations now include merged `dependencies` metadata and derived `security` requirements from both explicit and injected websocket dependencies.
11. Test client lifecycle helpers:
   - `TestClient` now starts app startup hooks lazily on first request/connect, supports explicit `start()` / `close()`, and runs shutdown hooks automatically on `deinit`.
12. Trace context propagation:
   - `tracestate` headers are now captured into request dependency state and propagated through trace/access-log sink payloads.
13. Proxy header extraction behavior:
   - proxy metadata extraction now parses RFC `Forwarded` header values (`for`/`proto`) with precedence over `X-Forwarded-For`/`X-Forwarded-Proto`.

## Migration Actions

1. If your CI depended on progressive parity thresholds, update expectations to full-coverage gating.
2. Set `PERF_GATE_MODE` explicitly in CI:
   - use `shared` on non-dedicated runners,
   - use `strict` on dedicated perf runners.
3. For cloud command consumers, adopt provider-specific outputs when integrating deployment automation:
   - `zigmund cloud --provider docker --emit-dir deploy`
   - `zigmund cloud --provider flyio --emit-dir deploy`
4. Optional auth behavior can be migrated explicitly:
   - keep `Security(...)` / `SecurityNamed(...)` for required-auth behavior,
   - use `SecurityOptional(...)` / `SecurityNamedOptional(...)` for optional auth behavior when scopes are empty.
5. For provider lifecycle hooks, attach cleanup at marker definition:
   - `Depends(myProvider, .{ .cleanup = myCleanup })`
   - cleanup is request-scoped; app-scoped cache + cleanup is intentionally rejected at compile-time.
6. Existing websocket handlers can remain unchanged.
   - Optionally migrate to request-aware signatures when path/header/query state is needed inside websocket handlers.
7. For lifecycle-sensitive integration tests, use `TestClient.start()` / `TestClient.close()` when you need explicit hook boundaries; otherwise lazy startup + `deinit` shutdown remains automatic.

## Compatibility Notes

1. No runtime compatibility break in HTTP request/response contract for existing handlers.
2. CLI output format for `zigmund cloud` now includes provider/deploy descriptors; consumers should treat additional JSON fields as forward-compatible.
