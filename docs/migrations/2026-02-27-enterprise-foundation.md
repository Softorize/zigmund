# 2026-02-27 Enterprise Foundation

## Breaking/Behavioral Changes

1. Parity coverage gates now enforce full matrix completion (`stub=0`, `missing=0`) against the pinned FastAPI docs baseline.
2. Performance regression checks now run in two modes:
   - `shared`: relaxed thresholds for shared CI runners.
   - `strict`: enterprise thresholds for dedicated benchmark environments.
3. `zigmund cloud` now supports provider-aware planning (`--provider`) and scaffold emission (`--emit-dir`) for deployment files.
4. Release-channel automation has been introduced (`nightly|alpha|beta|rc|stable`) with channel-aware release metadata.

## Migration Actions

1. If your CI depended on progressive parity thresholds, update expectations to full-coverage gating.
2. Set `PERF_GATE_MODE` explicitly in CI:
   - use `shared` on non-dedicated runners,
   - use `strict` on dedicated perf runners.
3. For cloud command consumers, adopt provider-specific outputs when integrating deployment automation:
   - `zigmund cloud --provider docker --emit-dir deploy`
   - `zigmund cloud --provider flyio --emit-dir deploy`

## Compatibility Notes

1. No runtime compatibility break in HTTP request/response contract for existing handlers.
2. CLI output format for `zigmund cloud` now includes provider/deploy descriptors; consumers should treat additional JSON fields as forward-compatible.
