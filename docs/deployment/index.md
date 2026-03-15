# Deployment

Guides for deploying Zigmund applications to production environments.

---

## Topics

- [Docker](docker.md) -- Build minimal Docker images for Zigmund applications using multi-stage builds. Covers base image selection, build caching, and container best practices for Zig binaries.

- [Production Configuration](production.md) -- Production server settings: worker count, timeouts, keep-alive, request size limits, logging levels, and environment-based configuration.

- [TLS and HTTPS](tls.md) -- Configure TLS certificates directly in Zigmund or terminate TLS at a reverse proxy. Covers certificate paths, HTTPS redirect middleware, and HSTS headers.

- [Reverse Proxy](reverse-proxy.md) -- Run Zigmund behind Nginx, Caddy, HAProxy, or a cloud load balancer. Covers proxy headers (`X-Forwarded-For`, `X-Forwarded-Proto`), trusted hosts, and the `root_path` setting.

- [Cloud Deployment](cloud.md) -- Deploy to cloud platforms using the `zigmund cloud` CLI command. Covers platform-specific configuration and the Zigmund cloud deployment workflow.

- [Monitoring and Observability](monitoring.md) -- Integrate metrics, structured logging, health checks, and distributed tracing. Covers the built-in `/metrics` endpoint and correlation ID middleware.
