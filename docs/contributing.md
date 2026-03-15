# Contributing to Zigmund

Thank you for your interest in contributing to Zigmund. This guide covers how to set up your development environment, run tests, and submit changes.

---

## Prerequisites

- **Zig 0.15.2** -- Zigmund targets Zig 0.15.2. Install it from [ziglang.org/download](https://ziglang.org/download/) or use a version manager such as [zigup](https://github.com/marler32/zigup).
- **Git** -- for version control and cloning the repository.

---

## Getting Started

### Clone the Repository

```bash
git clone https://github.com/Softorize/zigmund.git
cd zigmund
```

### Build

```bash
zig build
```

This compiles the framework, CLI, and all examples.

### Run Tests

```bash
zig build test
```

This runs the full test suite, including unit tests embedded in source files and integration tests under `tests/`.

---

## Parity System

Zigmund maintains a parity tracking system that maps features to their FastAPI equivalents. This helps identify gaps and track implementation coverage.

### Generate a Parity Report

```bash
zig build parity-report
```

Produces a summary of implemented features versus the FastAPI feature matrix.

### Generate Parity Stubs

```bash
zig build parity-stubs
```

Scaffolds stub files for unimplemented parity features, making it easy to pick up new work.

---

## Code Style

- Use standard Zig formatting. Run `zig fmt` before committing:

```bash
zig fmt src/
```

- Follow existing naming conventions in the codebase: `snake_case` for functions and variables, `PascalCase` for types.
- Keep functions focused and short. Prefer explicit error handling over optional returns where the failure mode is meaningful.
- Add doc comments (`///`) to public declarations.

---

## Pull Request Process

1. **Fork the repository** and create a feature branch from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```

2. **Make your changes.** Write tests for new functionality.

3. **Run the full test suite** to verify nothing is broken:
   ```bash
   zig build test
   ```

4. **Format your code:**
   ```bash
   zig fmt src/
   ```

5. **Commit and push** to your fork:
   ```bash
   git add .
   git commit -m "Add your feature description"
   git push origin feat/your-feature-name
   ```

6. **Open a pull request** against `main` on [github.com/Softorize/zigmund](https://github.com/Softorize/zigmund).

### PR Guidelines

- Keep pull requests focused on a single change. Split unrelated changes into separate PRs.
- Include a clear description of what the PR does and why.
- Reference any related issues (e.g., "Closes #42").
- Ensure CI passes before requesting review.

---

## Reporting Issues

Report bugs and request features at [github.com/Softorize/zigmund/issues](https://github.com/Softorize/zigmund/issues).

When reporting a bug, include:

- Zig version (`zig version`).
- Operating system and architecture.
- Minimal reproduction steps or a code snippet.
- Expected behavior versus actual behavior.
- Any error messages or stack traces.

---

## Directory Structure

```
zigmund/
  src/
    core/           -- Application, router, lifecycle management, exception handling
    runtime/        -- HTTP server, WebSocket server, reverse proxy, server configuration
    params/         -- Parameter markers and injection (path, query, header, cookie)
    deps/           -- Dependency injection graph
    schema/         -- JSON schema derivation and validation
    openapi/        -- OpenAPI specification generator and documentation UI
    security/       -- Authentication and security schemes
    integrations/   -- Extension points for third-party integrations
    testing/        -- Test client for integration testing
    middleware/     -- Built-in middleware (CORS, CSRF, compression, rate limiting, etc.)
    cli/            -- CLI entrypoint and command handling
    http/           -- HTTP request/response types
    template/       -- Template rendering
    assets/         -- Static assets (Swagger UI, ReDoc)
  examples/
    parity/         -- Parity examples mapping FastAPI features to Zigmund
  tests/
    conformance/    -- Conformance test suites
    interop/        -- Interoperability tests
    parity/         -- Parity validation tests
    perf/           -- Performance benchmarks
    reliability/    -- Reliability and stress tests
  tools/
    parity/         -- Parity matrix scripts and tooling
    perf/           -- Performance measurement tools
    release/        -- Release automation scripts
    reliability/    -- Reliability testing tools
  docs/             -- Documentation
```

---

## License

By contributing to Zigmund, you agree that your contributions will be licensed under the same license as the project. See the [LICENSE](../LICENSE) file for details.
