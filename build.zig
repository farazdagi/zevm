const std = @import("std");
const build_options = @import("build/options.zig");
const deps = @import("build/deps.zig");
const modules = @import("build/modules.zig");
const tests = @import("build/tests.zig");
const benchmarks = @import("build/benchmarks.zig");
const fixtures = @import("build/fixtures.zig");

pub fn build(b: *std.Build) void {
    const opts = build_options.parse(b);
    const native_deps = deps.build(b, opts.target, opts.optimize);
    const zevm = modules.createZevmModule(b, native_deps, opts.target, opts.optimize);

    // Executable
    const exe = b.addExecutable(.{
        .name = "zevm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = opts.target,
            .optimize = opts.optimize,
            .imports = &.{.{ .name = "zevm", .module = zevm }},
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the app").dependOn(&run.step);

    // Tests, benchmarks, fixtures
    tests.setup(b, zevm, opts);
    benchmarks.setup(b, zevm, opts);
    fixtures.setup(b);
}
