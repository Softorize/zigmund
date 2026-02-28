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
19. Trace/access observability payload extension:
   - W3C `baggage` header values are now captured into request dependency state as `baggage`.
   - `App.TraceEvent` and `App.AccessLogEvent` now include additive `baggage` fields.
   - JSON structured trace/access logs now emit `baggage`.
20. Routes CLI JSON dependency metadata extension:
   - `zigmund routes --json` now includes detailed dependency objects for HTTP and websocket routes:
     - `dependencies_detail`,
     - `injected_dependencies_detail`.
   - each dependency detail entry includes:
     - `name`,
     - `required`,
     - `use_cache`,
     - `cache_scope`,
     - `depends_on`,
     - `scopes`.
21. Runtime socket/tcp policy CLI extension:
   - `zigmund serve` and `zigmund dev` now support:
     - `--recv-buffer-bytes <n>`,
     - `--send-buffer-bytes <n>`,
     - `--reuse-address|--no-reuse-address`.
   - lifecycle startup audit payloads now include `reuse_address` for runtime-policy visibility.
22. OAuth2 helper/API parity extension:
   - `OAuth2AuthorizationCodeBearer` now includes `scopes` for parity with other OAuth2 bearer helper types.
   - conformance now validates authorization-code bearer resolver behavior (`auto_error` + bearer extraction).
   - OpenAPI conformance now validates full OAuth2 flow object emission (`implicit`, `password`, `clientCredentials`, `authorizationCode`).
23. API-key auth failure semantics hardening:
   - when a route/websocket dependency maps to an API-key security scheme, unauthorized outcomes now return `403 Forbidden` (instead of fallback bearer `401` semantics).
   - API-key auth failures no longer emit `WWW-Authenticate: Bearer` fallback headers.
24. Route guardrail API/runtime extension:
   - `RouteOptions` now includes `max_header_bytes` for route-level header-size policy control.
   - runtime route guardrail enforcement now applies route-level header/query/body overrides (`max_header_bytes`, `max_query_bytes`, `max_body_bytes`).
   - `zigmund routes --json` now emits HTTP `max_header_bytes` policy metadata alongside query/body limits.
25. OpenAPI route-policy metadata extension:
   - HTTP operations now emit `x-zigmund-route-policy` when route guardrails/strictness are configured.
   - extension payload includes additive route policy controls:
     - `strict_validation`,
     - `max_header_bytes`,
     - `max_query_bytes`,
     - `max_body_bytes`.
26. Response-model transform hook extension:
   - response model types can now define `zigmund_response_transform(value: *std.json.Value, allocator: std.mem.Allocator) !void`.
   - when `RouteOptions.response_model` is configured, the transform hook executes before include/exclude/default/null/alias shaping rules.
27. Model-level request validation hook extension:
   - marker value types can now define `zigmund_validate(...)` hooks for custom domain validation.
   - supported signatures:
     - `fn(ValueType) !void`,
     - `fn(ValueType, *Request) !void`.
   - failed hooks now emit 422 validation issues with `type="model_validator"` and structured error-name input.
28. Auth failure handler extension:
   - reusable auth failure handlers can now be registered on `App`:
     - `setUnauthorizedHandler(...)`,
     - `setInsufficientScopeHandler(...)`.
   - when configured, handlers override default unauthorized/insufficient-scope response construction (HTTP + websocket handshake paths).
29. Response-model validation hook extension:
   - response model types can now define `zigmund_response_validate(value: *const std.json.Value, allocator: std.mem.Allocator) !void`.
   - validation hook executes after response-model transform/include/exclude/default/null/alias shaping and before final payload serialization.
   - failed hooks trigger deterministic internal-server-error response fallback.
30. OpenAPI JSON Schema dialect extension:
   - `AppConfig` now includes `json_schema_dialect` (default: `https://json-schema.org/draft/2020-12/schema`).
   - generated OpenAPI documents now emit top-level `jsonSchemaDialect` when configured.
   - emission can be disabled by setting `json_schema_dialect = null`.
31. OpenAPI CLI dialect controls:
   - `zigmund openapi` now supports:
     - `--json-schema-dialect <uri>` to override emitted `jsonSchemaDialect`,
     - `--no-json-schema-dialect` to suppress `jsonSchemaDialect` emission in CLI-generated output.
32. OAuth2 scope utility extension:
   - `OAuth2PasswordRequestForm` now exposes scope helpers:
     - `parsedScopesAlloc(...)` for tokenized scope-list extraction,
     - `applyGrantedScopes(...)` for request dependency-context scope seeding.
   - new public utility export added:
     - `parseScopesRawAlloc(...)` for comma/space-delimited scope set parsing.
33. OpenAPI security requirement semantics hardening:
   - route/websocket `security` requirements now emit combined AND semantics in a single requirement object when multiple security schemes are present.
   - duplicate scheme entries across explicit/injected dependencies are merged with scope-union semantics.
34. Cloud CLI deploy workflow extension:
   - `zigmund cloud` now supports deploy execution controls:
     - `--execute` to run provider deploy commands,
     - `--dry-run` to emit resolved deploy command payload without execution,
     - `--image <tag>` (`--image-tag`) to override docker image tag used in deploy execution.
   - provider execution support:
     - `docker`: executes `docker build -t <tag> -f Dockerfile .`,
     - `flyio`: executes `flyctl deploy`,
     - `generic`: execution intentionally rejected (`CloudDeployUnsupportedProvider`).
35. OpenAPI explicit security alternatives extension:
   - `RouteOptions` and `WebSocketRouteOptions` now include `openapi_security` for explicit OpenAPI `security` requirement arrays (OR across objects, AND within object).
   - explicit `openapi_security` values override dependency-derived security emission when present.
   - duplicate scheme entries within the same alternative are scope-union merged.
36. HTTP write-timeout runtime extension:
   - `ServerConfig` now includes `write_timeout_ms` for socket-level HTTP response write timeout control.
   - CLI `serve`/`dev` now accept `--write-timeout-ms <n>`.
   - startup audit config payloads now emit `write_timeout_ms`.
37. Request-id header customization extension:
   - `AppConfig` now includes `request_id_header` (default: `x-request-id`) for inbound/outbound request-id propagation header naming.
   - empty header values fallback to default `x-request-id`.
38. Overload retry policy extension:
   - `ServerConfig` now includes `overload_retry_after_seconds` (default: `1`) for `Retry-After` header emission on connection-overload (`503`) responses.
   - CLI `serve`/`dev` now accept:
     - `--overload-retry-after-seconds <n>`,
     - `--no-overload-retry-after` (sets overload retry header policy to disabled/`0`).
39. Graceful-drain response hardening:
   - new incoming connections during shutdown/drain now receive explicit `503 Service Unavailable` responses with `server shutting down` payload (instead of silent close), reusing configured overload retry policy.

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
13. If you consume trace/access sink payloads programmatically, update schemas/handlers to include the additive `baggage` field.
14. If your CI/ops tooling parses route inventory JSON, migrate from count-only dependency fields to the new detailed dependency arrays when richer policy/governance checks are needed.
15. If you operate runtime policy through CLI wrappers, include new socket/tcp knobs (`recv/send buffer`, `reuse_address`) where explicit transport tuning is required.
16. For OAuth2 helper usage, you can now configure `scopes` on `OAuth2AuthorizationCodeBearer` in the same pattern as other OAuth2 bearer helper types.
17. If downstream consumers depended on bearer challenge headers for API-key protected routes, update expectations: API-key failures now return `403` without `WWW-Authenticate`.
18. If you enforce header-size limits per endpoint, migrate to route-level `max_header_bytes` instead of only global `ServerConfig.max_header_bytes`.
19. If downstream OpenAPI consumers lint/enforce vendor extensions, allowlist `x-zigmund-route-policy` for routes that configure strictness or HTTP guardrails.
20. If your response-model types require custom serialization logic, migrate from handler-local ad hoc JSON mutation to model-local `zigmund_response_transform(...)` hooks for deterministic post-handler shaping.
21. If request payload/domain validation previously lived only in handlers, migrate it into model-local `zigmund_validate(...)` hooks to produce standardized 422 validation issue payloads.
22. If your platform requires custom auth failure envelopes/headers, migrate from middleware-based response patching to `setUnauthorizedHandler(...)` / `setInsufficientScopeHandler(...)` for deterministic security failure responses.
23. If response payload invariants were previously validated ad hoc in handlers/middleware, migrate them into model-local `zigmund_response_validate(...)` hooks for deterministic post-shaping validation.
24. If your OpenAPI consumers require explicit JSON Schema dialect pinning, adopt `AppConfig.json_schema_dialect`; set to `null` only when external tooling enforces/infers dialect out-of-band.
25. If OpenAPI artifact generation runs via CLI in CI/CD, migrate CLI invocations to use `--json-schema-dialect` / `--no-json-schema-dialect` where dialect policy differs by environment.
26. If OAuth2 password-flow handlers currently tokenize `scope` manually, migrate to `OAuth2PasswordRequestForm.parsedScopesAlloc(...)` and/or `applyGrantedScopes(...)` for consistent scope parsing and dependency-state integration.
27. If downstream OpenAPI tooling assumed one-item-per-object security arrays for multi-scheme routes, update parsers to consume standard combined requirement-object semantics (AND within object, OR across array entries).
28. If CI/CD pipelines currently treat `zigmund cloud` as plan-only, migrate to `--execute` / `--dry-run` where deployment orchestration should be performed directly by Zigmund CLI; use `--image <tag>` for deterministic docker artifact naming.
29. If OpenAPI route security policy requires explicit OR alternatives or non-default ordering, migrate route/websocket declarations to `openapi_security` for deterministic security-array authoring independent of dependency wiring.
30. If runtime policy wrappers/scripts currently set only header/body/idle timeouts, migrate to include `--write-timeout-ms` when explicit response write-deadline control is required.
31. If edge/gateway policy requires a non-default request correlation header, migrate `AppConfig.request_id_header` to your organization-standard header name and update tests/clients accordingly.
32. If your traffic-management policy relies on explicit retry hints during overload, migrate runtime wrappers to set `--overload-retry-after-seconds`; use `--no-overload-retry-after` when `Retry-After` must be suppressed.
33. If health-check or client logic previously interpreted immediate connection close as shutdown signal, migrate to handle explicit `503` shutdown responses during drain windows.

## Compatibility Notes

1. No runtime compatibility break in HTTP request/response contract for existing handlers.
2. CLI output format for `zigmund cloud` now includes provider/deploy descriptors; consumers should treat additional JSON fields as forward-compatible.
3. Deploy execution remains opt-in; existing `zigmund cloud` usage without `--execute` remains non-mutating.
