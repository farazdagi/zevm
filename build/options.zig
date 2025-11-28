//! Build options parsing and configuration.

const std = @import("std");

/// All build options parsed from command line.
pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    test_filter: ?[]const u8,
    test_timing: bool,
    fail_first: bool,
    test_target: ?[]const u8,
    bench_optimize: std.builtin.OptimizeMode,
    bench_target: ?[]const u8,
};

/// Parse all build options from the build system.
pub fn parse(b: *std.Build) Options {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Test options
    const test_filter = b.option([]const u8, "filter", "Filter tests by name");
    const test_timing = b.option(bool, "timing", "Show timing for each test") orelse true;
    const test_fail_first = b.option(bool, "fail-first", "Stop on first test failure") orelse false;
    var test_target = b.option([]const u8, "test-target", "Run specific test target (lib, main, integration, conformance, or tests/<file>)");

    // Also check for --test-target in b.args (when using `zig build test -- --test-target=lib`)
    if (test_target == null) {
        const prefix = "--test-target=";
        for (b.args orelse &.{}) |arg| {
            if (std.mem.startsWith(u8, arg, prefix)) {
                test_target = arg[prefix.len..];
                break;
            }
        }
    }

    // Benchmark options
    const bench_optimize = b.option(std.builtin.OptimizeMode, "bench-optimize", "Optimization mode for benchmarks") orelse .Debug;
    const bench_target = b.option([]const u8, "bench-target", "Run specific benchmark (e.g., big, stack, or bench/<file>)");

    return .{
        .target = target,
        .optimize = optimize,
        .test_filter = test_filter,
        .test_timing = test_timing,
        .fail_first = test_fail_first,
        .test_target = test_target,
        .bench_optimize = bench_optimize,
        .bench_target = bench_target,
    };
}
