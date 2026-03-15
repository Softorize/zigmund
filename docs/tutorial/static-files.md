# Static Files

Serve static assets -- HTML, CSS, JavaScript, images -- directly from a directory on disk, with configurable URL prefixes and cache control.

## Overview

Most web applications need to serve at least a few static files: a favicon, a CSS stylesheet, client-side JavaScript, or documentation pages. Zigmund provides `zigmund.mountStaticFiles` to map a URL prefix to a directory, so the framework serves files directly without requiring a separate web server or CDN during development.

Static file serving is intentionally simple. For production deployments with heavy static traffic, consider placing a reverse proxy (nginx, Caddy) or CDN in front of Zigmund and using this feature only for development or low-traffic scenarios.

## Example

```zig
const std = @import("std");
const zigmund = @import("zigmund");

fn readStaticInfo(req: *zigmund.Request, allocator: std.mem.Allocator) !zigmund.Response {
    _ = req;
    return zigmund.Response.json(allocator, .{
        .static_prefix = "/tutorial/static-files/assets",
        .example_file = "/tutorial/static-files/assets/index.html",
    });
}

pub fn buildExample(app: *zigmund.App) !void {
    try zigmund.mountStaticFiles(
        app,
        "/tutorial/static-files/assets",
        "examples/parity/assets/static",
        .{
            .include_in_schema = true,
            .cache_control = "public, max-age=300",
        },
    );

    try app.get("/tutorial/static-files", readStaticInfo, .{
        .summary = "Static files mount example",
        .tags = &.{ "parity", "tutorial" },
        .operation_id = "tutorial_static_files_info",
    });
}
```

## How It Works

1. **Call `mountStaticFiles`.** The function takes four arguments:
   - `app` -- The application instance.
   - URL prefix (`"/tutorial/static-files/assets"`) -- All requests under this path are matched against the directory.
   - Directory path (`"examples/parity/assets/static"`) -- The filesystem directory containing your static files. Relative paths are resolved from the working directory.
   - Options struct -- Controls caching and OpenAPI visibility.

2. **URL-to-file mapping.** A request to `/tutorial/static-files/assets/index.html` maps to the file `examples/parity/assets/static/index.html`. Subdirectories are traversed automatically, so `/assets/css/style.css` maps to `static/css/style.css`.

3. **Cache control.** `.cache_control = "public, max-age=300"` sets the `Cache-Control` response header on every static file response. This tells browsers and proxies to cache files for 300 seconds (5 minutes). Adjust this value for your deployment scenario.

4. **OpenAPI visibility.** `.include_in_schema = true` adds the static file routes to the generated OpenAPI specification. Set this to `false` (the default) if you do not want static asset paths cluttering your API documentation.

5. **Combine with regular routes.** The `/tutorial/static-files` route is a normal handler that returns JSON. It coexists with the static mount, demonstrating that static files and dynamic endpoints live under the same application.

## Key Points

- Zigmund determines the MIME type from the file extension (`.html` becomes `text/html`, `.css` becomes `text/css`, etc.). Unknown extensions default to `application/octet-stream`.
- Path traversal attacks (e.g., `/../../../etc/passwd`) are prevented by the framework. Requests that resolve outside the configured directory receive a `404 Not Found`.
- The directory path is validated at startup. If it does not exist or is not readable, `mountStaticFiles` returns an error.
- Static file serving does not support directory listings. Requesting a directory path without a filename returns `404` unless an `index.html` file is present (behavior depends on framework configuration).
- For single-page applications, you may want to combine `mountStaticFiles` with a catch-all route that serves `index.html` for unmatched paths.

## See Also

- [First Steps](first-steps.md) -- Basic application setup and route registration.
- [Custom Index Page](index-page.md) -- Replace the default root page with a custom handler or static file.
- [Middleware](middleware.md) -- Add headers or logging to all responses, including static files.
- [CORS](cors.md) -- Configure cross-origin access for static assets consumed by browser clients.
