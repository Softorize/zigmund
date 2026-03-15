# Docker Deployment

This guide covers building and deploying Zigmund applications as Docker containers, including multi-stage builds, Docker Compose configuration, and production best practices.

---

## Multi-Stage Dockerfile

A multi-stage build produces a minimal final image by separating the build environment from the runtime environment. Zig produces fully static binaries (when targeting musl), so the runtime image can be extremely small.

```dockerfile
# Stage 1: Build
FROM ghcr.io/ziglang/zig:0.15.2 AS builder

WORKDIR /app

# Copy dependency manifest first for better layer caching
COPY build.zig build.zig.zon ./

# Copy source code
COPY src/ src/
COPY examples/ examples/

# Build with release optimizations
RUN zig build -Doptimize=.ReleaseFast

# Stage 2: Runtime
FROM alpine:3.21

# Install only what is needed at runtime
RUN apk add --no-cache ca-certificates

WORKDIR /app

# Copy the compiled binary from the build stage
COPY --from=builder /app/zig-out/bin/myapp /app/myapp

# Run as non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080

ENTRYPOINT ["/app/myapp"]
```

### Using a Scratch Image

For the smallest possible image, use `scratch` instead of Alpine. This works well when the Zig binary is fully statically linked (the default when targeting `x86_64-linux-musl` or `aarch64-linux-musl`):

```dockerfile
# Stage 2: Runtime (scratch variant)
FROM scratch

COPY --from=builder /app/zig-out/bin/myapp /myapp
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

EXPOSE 8080

ENTRYPOINT ["/myapp"]
```

> **Note:** Scratch images have no shell, package manager, or debugging tools. Use Alpine if you need to exec into containers for troubleshooting.

---

## Environment Variables for Configuration

Pass configuration to your Zigmund application through environment variables. A common pattern is to read these in your `main()` and pass them to `app.serve()`:

```dockerfile
ENV ZIGMUND_HOST=0.0.0.0
ENV ZIGMUND_PORT=8080
ENV ZIGMUND_WORKERS=4
ENV ZIGMUND_LOG_LEVEL=info
```

In your application code, read these at startup:

```zig
const host = std.process.getEnvVarOwned(allocator, "ZIGMUND_HOST") catch "0.0.0.0";
const port_str = std.process.getEnvVarOwned(allocator, "ZIGMUND_PORT") catch "8080";
const port = std.fmt.parseInt(u16, port_str, 10) catch 8080;

try app.serve(.{
    .host = host,
    .port = port,
    .worker_count = 4,
});
```

---

## Docker Compose

A complete Docker Compose configuration for a Zigmund application with a reverse proxy and database:

```yaml
version: "3.9"

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - ZIGMUND_HOST=0.0.0.0
      - ZIGMUND_PORT=8080
      - ZIGMUND_WORKERS=4
      - DATABASE_URL=postgres://user:pass@db:5432/mydb
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 512M
        reservations:
          cpus: "0.5"
          memory: 128M
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
```

---

## Health Check Configuration

Docker health checks verify that your application is responding. Zigmund provides a built-in health check middleware that you can enable:

```zig
const health = @import("zigmund").middleware.health;
app.addHealthCheck(health.HealthCheckConfig{
    .path = "/health",
});
```

In the Dockerfile or Compose file, point the health check at this endpoint:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD wget --spider -q http://localhost:8080/health || exit 1
```

For scratch-based images without `wget`, you can build a small health check binary in Zig and include it in the image, or use Docker Compose health checks with `curl` from a sidecar.

---

## CLI Command

The Zigmund CLI provides a convenience command for Docker deployments:

```bash
zigmund cloud --provider docker
```

This generates a production-ready Dockerfile and Docker Compose configuration tailored to your project structure.

---

## Production Considerations

### Resource Limits

Always set CPU and memory limits in production to prevent a single container from consuming all host resources:

```yaml
deploy:
  resources:
    limits:
      cpus: "2.0"
      memory: 512M
    reservations:
      cpus: "0.5"
      memory: 128M
```

### Logging

Configure containers to use a structured logging driver. Zigmund supports structured access logs via the `structured_access_logs` setting in `AppConfig`:

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "5"
```

### Restart Policies

Use `unless-stopped` or `always` to ensure your application recovers from crashes:

```yaml
restart: unless-stopped
```

For orchestrated environments (Docker Swarm, Kubernetes), use the platform's native restart and rescheduling mechanisms instead.

### Security

- Run containers as a non-root user (shown in the Dockerfile above).
- Do not store secrets in environment variables within Dockerfiles. Use Docker secrets, mounted secret files, or a secrets manager.
- Keep base images up to date to receive security patches.
- Use `.dockerignore` to exclude unnecessary files from the build context:

```
.git
zig-cache
zig-out
test_*
docs/
```

### Build Caching

Zig's build system uses an internal cache under `zig-cache/`. To speed up Docker builds, copy `build.zig` and `build.zig.zon` before copying `src/` so that dependency resolution is cached in a separate layer. The example Dockerfile above follows this pattern.
