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

## Compatibility Notes

1. No runtime compatibility break in HTTP request/response contract for existing handlers.
2. CLI output format for `zigmund cloud` now includes provider/deploy descriptors; consumers should treat additional JSON fields as forward-compatible.
