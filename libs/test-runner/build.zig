const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the test-runner module
    _ = b.addModule("test-runner", .{
        .root_source_file = b.path("runner.zig"),
        .target = target,
        .optimize = optimize,
    });
}
