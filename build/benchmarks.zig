//! Benchmark discovery and execution.
//!
//! Auto-discovers benchmark files in bench/ directory and creates executable steps for running them.

const std = @import("std");
const options = @import("options.zig");

const Build = std.Build;
const Module = Build.Module;
const Step = Build.Step;
const Run = Build.Step.Run;

const Benchmark = struct {
    run: *Run,
    name: []const u8,
};

/// Setup benchmark steps.
pub fn setup(b: *Build, zevm_module: *Module, opts: options.Options) void {
    const bench_step = b.step("bench", "Run benchmarks");
    const benchmarks = discoverBenchmarks(b, zevm_module, opts) catch return;

    if (opts.bench_target) |target| {
        runSpecific(b, bench_step, target, benchmarks);
    } else {
        for (benchmarks) |bm| bench_step.dependOn(&bm.run.step);
    }
}

fn discoverBenchmarks(b: *Build, zevm_module: *Module, opts: options.Options) ![]const Benchmark {
    const dir = std.fs.cwd().openDir("bench", .{ .iterate = true }) catch |err| {
        return if (err == error.FileNotFound) &.{} else err;
    };
    var dir_mut = dir;
    defer dir_mut.close();

    var benchmarks = std.ArrayList(Benchmark){};
    var iter = dir_mut.iterate();

    while (try iter.next()) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;

        const name = entry.name[0 .. entry.name.len - 4];
        const exe = b.addExecutable(.{
            .name = b.fmt("bench-{s}", .{name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("bench/{s}", .{entry.name})),
                .target = opts.target,
                .optimize = opts.bench_optimize,
                .imports = &.{.{ .name = "zevm", .module = zevm_module }},
            }),
        });

        const run = b.addRunArtifact(exe);
        if (b.args) |args| run.addArgs(args);

        benchmarks.append(b.allocator, .{ .run = run, .name = b.dupe(entry.name) }) catch unreachable;
    }

    return benchmarks.toOwnedSlice(b.allocator);
}

fn runSpecific(b: *Build, step: *Step, target: []const u8, benchmarks: []const Benchmark) void {
    // Normalize target to filename
    const file = if (std.mem.startsWith(u8, target, "bench/"))
        target[6..]
    else if (std.mem.endsWith(u8, target, ".zig"))
        target
    else
        b.fmt("{s}.zig", .{target});

    for (benchmarks) |bm| {
        if (std.mem.eql(u8, bm.name, file)) {
            step.dependOn(&bm.run.step);
            return;
        }
    }

    std.log.err("Benchmark not found: {s}", .{file});
    std.log.err("Available:", .{});
    for (benchmarks) |bm| std.log.err("  - {s}", .{bm.name[0 .. bm.name.len - 4]});
    std.process.exit(1);
}
