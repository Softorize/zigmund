const runtime = @import("../runtime/mod.zig");

pub const CompatibilityAdapters = struct {
    enable_proxy_mode: bool = false,
    enable_wsgi_analog: bool = false,
    trusted_proxy_headers: bool = true,
    trusted_proxy_forwarded_header: bool = true,
    trusted_proxy_x_forwarded_headers: bool = true,
    trusted_proxy_cidrs: []const []const u8 = &.{},

    pub fn applyToServerConfig(self: CompatibilityAdapters, cfg: *runtime.ServerConfig) void {
        if (self.enable_proxy_mode) {
            cfg.trusted_proxy_headers = self.trusted_proxy_headers;
            cfg.trusted_proxy_forwarded_header = self.trusted_proxy_forwarded_header;
            cfg.trusted_proxy_x_forwarded_headers = self.trusted_proxy_x_forwarded_headers;
            cfg.trusted_proxy_cidrs = self.trusted_proxy_cidrs;
            return;
        }

        cfg.trusted_proxy_headers = false;
        cfg.trusted_proxy_forwarded_header = false;
        cfg.trusted_proxy_x_forwarded_headers = false;
        cfg.trusted_proxy_cidrs = &.{};
    }
};

test "compatibility adapters update proxy trust config" {
    var cfg = runtime.ServerConfig{};
    const adapters = CompatibilityAdapters{
        .enable_proxy_mode = true,
        .trusted_proxy_headers = true,
        .trusted_proxy_forwarded_header = true,
        .trusted_proxy_x_forwarded_headers = false,
        .trusted_proxy_cidrs = &.{"10.0.0.0/8"},
    };
    adapters.applyToServerConfig(&cfg);

    try @import("std").testing.expect(cfg.trusted_proxy_headers);
    try @import("std").testing.expect(cfg.trusted_proxy_forwarded_header);
    try @import("std").testing.expect(!cfg.trusted_proxy_x_forwarded_headers);
    try @import("std").testing.expectEqual(@as(usize, 1), cfg.trusted_proxy_cidrs.len);
}
