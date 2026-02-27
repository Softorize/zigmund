# Zigmund Migration Notes

Pre-`1.0.0`, breaking changes are allowed but every milestone must ship explicit migration notes.

## Rules

1. Add a dated markdown file (`YYYY-MM-DD-*.md`) for each release milestone that changes runtime behavior or public APIs.
2. Include at minimum:
   - Changed surface (API/CLI/config/runtime behavior)
   - Migration action required by users
   - Backward-compatibility impact and fallback notes
3. Keep old notes immutable; add a new file for follow-up changes.
