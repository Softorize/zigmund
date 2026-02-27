const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigmund_mod = b.addModule("zigmund", .{
        .root_source_file = b.path("src/zigmund.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigmund", .module = zigmund_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zigmund",
        .root_module = cli_mod,
    });
    applyNativeTlsLinks(exe);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run Zigmund CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const sbom_step = b.step("sbom", "Generate CycloneDX SBOM");
    const sbom_cmd = b.addRunArtifact(exe);
    sbom_cmd.step.dependOn(b.getInstallStep());
    sbom_cmd.addArgs(&.{ "sbom", "--out", "zigmund.sbom.json" });
    sbom_step.dependOn(&sbom_cmd.step);

    const test_step = b.step("test", "Run library and integration tests");

    const lib_tests = b.addTest(.{ .root_module = zigmund_mod });
    applyNativeTlsLinks(lib_tests);
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);

    const cli_tests = b.addTest(.{ .root_module = cli_mod });
    applyNativeTlsLinks(cli_tests);
    const run_cli_tests = b.addRunArtifact(cli_tests);
    test_step.dependOn(&run_cli_tests.step);

    const test_files = [_][]const u8{
        "tests/conformance/router_test.zig",
        "tests/conformance/openapi_test.zig",
        "tests/conformance/openapi_security_test.zig",
        "tests/conformance/security_scope_oauth_test.zig",
        "tests/conformance/dependencies_middleware_test.zig",
        "tests/conformance/handler_injection_test.zig",
        "tests/conformance/form_file_injection_test.zig",
        "tests/conformance/body_embed_test.zig",
        "tests/conformance/content_type_validation_test.zig",
        "tests/conformance/openapi_request_body_test.zig",
        "tests/conformance/openapi_parameters_test.zig",
        "tests/conformance/openapi_response_model_test.zig",
        "tests/conformance/openapi_advanced_objects_test.zig",
        "tests/conformance/docs_ui_endpoints_test.zig",
        "tests/conformance/openapi_include_in_schema_test.zig",
        "tests/conformance/include_router_merge_test.zig",
        "tests/conformance/optional_parameter_runtime_test.zig",
        "tests/conformance/exception_handler_test.zig",
        "tests/conformance/openapi_injected_dependencies_test.zig",
        "tests/conformance/response_model_runtime_shaping_test.zig",
        "tests/conformance/observability_test.zig",
        "tests/conformance/dependency_cleanup_test.zig",
        "tests/conformance/dependency_graph_scope_test.zig",
        "tests/conformance/provider_injection_runtime_test.zig",
        "tests/conformance/unauthorized_header_test.zig",
        "tests/conformance/openapi_components_operation_id_test.zig",
        "tests/conformance/openapi_customization_test.zig",
        "tests/conformance/websocket_security_test.zig",
        "tests/conformance/runtime_server_limits_test.zig",
        "tests/conformance/runtime_tls_config_test.zig",
        "tests/conformance/testclient_websocket_session_test.zig",
        "tests/conformance/integrations_test.zig",
        "tests/conformance/metrics_endpoint_test.zig",
        "tests/conformance/request_parsing_test.zig",
        "tests/conformance/validation_error_test.zig",
        "tests/conformance/parameter_constraints_strict_test.zig",
        "tests/conformance/testclient_cookie_persistence_test.zig",
        "tests/conformance/api_surface_snapshot_test.zig",
        "tests/parity/matrix_test.zig",
        "tests/perf/smoke_test.zig",
        "tests/interop/proxy_headers_test.zig",
    };

    for (test_files) |path| {
        const mod = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigmund", .module = zigmund_mod },
            },
        });
        const test_exe = b.addTest(.{ .root_module = mod });
        applyNativeTlsLinks(test_exe);
        const run_test_exe = b.addRunArtifact(test_exe);
        test_step.dependOn(&run_test_exe.step);
    }

    const parity_cmd = b.addSystemCommand(&.{ "sh", "tools/parity/fetch_fastapi_sitemap.sh" });
    const parity_step = b.step("parity-report", "Generate FastAPI parity matrix report");
    parity_step.dependOn(&parity_cmd.step);

    const parity_stubs_cmd = b.addSystemCommand(&.{ "sh", "tools/parity/generate_parity_stubs.sh" });
    const parity_stubs_step = b.step("parity-stubs", "Generate parity stub examples for missing FastAPI pages");
    parity_stubs_step.dependOn(&parity_stubs_cmd.step);

    const check_step = b.step("check", "Compile Zigmund without running");
    check_step.dependOn(&exe.step);
}

fn applyNativeTlsLinks(step: *std.Build.Step.Compile) void {
    step.linkLibC();
    step.linkSystemLibrary("ssl");
    step.linkSystemLibrary("crypto");

    if (pathExists("/opt/homebrew/include")) {
        step.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    }
    if (pathExists("/opt/homebrew/lib")) {
        step.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    }
    if (pathExists("/usr/local/include")) {
        step.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    }
    if (pathExists("/usr/local/lib")) {
        step.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    }
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}
