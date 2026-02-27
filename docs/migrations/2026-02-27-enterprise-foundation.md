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
14. Proxy trust policy controls:
   - `ServerConfig` now exposes independent trust toggles for forwarded header families:
     - `trusted_proxy_forwarded_header` (RFC `Forwarded`),
     - `trusted_proxy_x_forwarded_headers` (`X-Forwarded-*`).
   - CLI flags are now available to configure these independently:
     - `--trusted-proxy-forwarded-header|--no-trusted-proxy-forwarded-header`,
     - `--trusted-proxy-x-forwarded-headers|--no-trusted-proxy-x-forwarded-headers`.
15. Proxy context propagation behavior:
   - proxy extraction now includes forwarded host metadata (`host` from RFC `Forwarded` and fallback `X-Forwarded-Host`).
   - trusted proxy metadata is now seeded into request dependency context for runtime requests:
     - `client_ip`, `scheme`, `host`,
     - `zigmund.proxy.client_ip`, `zigmund.proxy.proto`, `zigmund.proxy.host`.
   - structured access logs now prefer trusted proxy client IP context (`zigmund.proxy.client_ip`) over raw peer socket address.
16. Runtime CLI/config parity improvement:
   - `zigmund serve` and `zigmund dev` now support `--max-query-bytes <n>` to configure query-size guardrails from CLI.
   - lifecycle startup audit payloads now include `max_query_bytes` for runtime-policy observability.
17. Access-log schema extension:
   - `App.AccessLogEvent` now includes `scheme` and `host`.
   - JSON structured access logs now emit `scheme` and `host` fields.
   - access-log emission now resolves `scheme`/`host` from trusted proxy dependency context first (`zigmund.proxy.proto` / `zigmund.proxy.host`), with host fallback to request `Host` header.
18. Routes CLI JSON schema extension:
   - `zigmund routes --json` now includes HTTP policy metadata:
     - `strict_validation`,
     - `max_query_bytes`,
     - `max_body_bytes`.
   - websocket route JSON entries now include runtime policy fields:
     - `idle_timeout_ms`,
     - `auto_pong`,
     - `ping_interval_ms`,
     - `pong_timeout_ms`,
     - `max_message_bytes`,
     - `max_pending_messages`,
     - `send_timeout_ms`.

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
8. If you rely on proxy metadata, set explicit trust policy for header families based on your edge topology:
   - disable RFC `Forwarded` trust when only legacy `X-Forwarded-*` is expected,
   - disable `X-Forwarded-*` trust when your edge emits only RFC `Forwarded`.
9. If downstream handlers or telemetry consumers need edge client metadata, migrate to dependency keys populated from trusted proxy context:
   - `req.dependency("client_ip")` / `req.dependency("scheme")` / `req.dependency("host")`,
   - or namespaced equivalents under `zigmund.proxy.*`.
10. If you manage runtime limits from CLI wrappers/scripts, add `--max-query-bytes` alongside existing `--max-header-bytes`/`--max-body-bytes` controls for explicit query guardrails.
11. If you consume `AccessLogEvent` programmatically, update sink handlers/schemas to accept the additive `scheme` and `host` fields.
12. If you parse `zigmund routes --json` output, update consumers to tolerate/additionally consume the new policy metadata fields on HTTP and websocket route objects.

## Compatibility Notes

1. No runtime compatibility break in HTTP request/response contract for existing handlers.
2. CLI output format for `zigmund cloud` now includes provider/deploy descriptors; consumers should treat additional JSON fields as forward-compatible.
