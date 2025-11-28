//! Test discovery and aggregation.

const std = @import("std");
const TestRunner = @import("../libs/test-runner/build.zig");
const options = @import("options.zig");

const Build = std.Build;
const Module = Build.Module;
const Compile = Build.Step.Compile;
const Run = Build.Step.Run;
const Step = Build.Step;

/// A test compile/run pair.
const TestPair = struct {
    compile: *Compile,
    run: *Run,
    name: []const u8,
};

/// Setup all test steps.
pub fn setup(b: *Build, zevm_module: *Module, opts: options.Options) void {
    const test_step = b.step("test", "Run tests");

    // Core tests
    const lib = addTest(b, zevm_module, opts, "lib");
    const exe = addTest(b, createExeModule(b, zevm_module, opts), opts, "main");

    // Discover integration and conformance tests
    const integration = discoverTests(b, zevm_module, opts, "tests/integration") catch &.{};
    const conformance = discoverTests(b, zevm_module, opts, "tests/conformance") catch &.{};

    // Route based on test target
    if (opts.test_target) |target| {
        routeTarget(b, test_step, target, opts, lib, exe, integration, conformance);
    } else {
        runAll(b, test_step, opts, lib, exe, integration, conformance);
    }
}

fn createExeModule(b: *Build, zevm_module: *Module, opts: options.Options) *Module {
    return b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
        .imports = &.{.{ .name = "zevm", .module = zevm_module }},
    });
}

fn addTest(b: *Build, module: *Module, opts: options.Options, name: []const u8) TestPair {
    const t = b.addTest(.{
        .root_module = module,
        .test_runner = .{ .path = b.path("libs/test-runner/runner.zig"), .mode = .simple },
    });
    const r = b.addRunArtifact(t);
    TestRunner.configureRunner(r, opts.test_filter, opts.test_timing, opts.fail_first, b.args);
    return .{ .compile = t, .run = r, .name = name };
}

fn discoverTests(b: *Build, zevm_module: *Module, opts: options.Options, dir: []const u8) ![]const TestPair {
    var files = try TestRunner.discoverTestFiles(b.allocator, dir);
    defer files.deinit(b.allocator);

    var tests = std.ArrayList(TestPair){};
    for (files.items) |file| {
        const path = b.fmt("{s}/{s}", .{ dir, file });
        const module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = opts.target,
            .optimize = opts.optimize,
            .imports = &.{.{ .name = "zevm", .module = zevm_module }},
        });
        var pair = addTest(b, module, opts, b.dupe(file));
        pair.run.addArg("--test-name");
        pair.run.addArg(path);
        tests.append(b.allocator, pair) catch unreachable;
    }
    return tests.toOwnedSlice(b.allocator);
}

fn routeTarget(
    b: *Build,
    step: *Step,
    target: []const u8,
    opts: options.Options,
    lib: TestPair,
    exe: TestPair,
    integration: []const TestPair,
    conformance: []const TestPair,
) void {
    if (std.mem.eql(u8, target, "lib")) {
        step.dependOn(&lib.run.step);
    } else if (std.mem.eql(u8, target, "main")) {
        step.dependOn(&exe.run.step);
    } else if (std.mem.eql(u8, target, "integration")) {
        runSuite(b, step, opts, integration);
    } else if (std.mem.eql(u8, target, "conformance")) {
        if (conformance.len == 0) std.log.warn("No conformance tests found in tests/conformance/", .{});
        runSuite(b, step, opts, conformance);
    } else if (std.mem.startsWith(u8, target, "tests/integration/")) {
        runSpecific(step, target["tests/integration/".len..], integration, "integration");
    } else if (std.mem.startsWith(u8, target, "tests/conformance/")) {
        runSpecific(step, target["tests/conformance/".len..], conformance, "conformance");
    } else {
        std.log.err("Unknown test target: {s}", .{target});
        std.log.err("Valid: lib, main, integration, conformance, tests/integration/<file>, tests/conformance/<file>", .{});
        std.process.exit(1);
    }
}

fn runSuite(b: *Build, step: *Step, opts: options.Options, tests: []const TestPair) void {
    if (tests.len == 0) return;

    var artifacts = std.ArrayList(*Compile){};
    var names = std.ArrayList([]const u8){};

    for (tests) |t| {
        step.dependOn(&t.run.step);
        artifacts.append(b.allocator, t.compile) catch unreachable;
        names.append(b.allocator, t.name) catch unreachable;
    }

    const agg = TestRunner.AggregateTestStep.create(b, artifacts, names, opts.test_filter, opts.fail_first, b.args);
    for (tests) |t| agg.step.dependOn(&t.run.step);
    step.dependOn(&agg.step);
}

fn runSpecific(step: *Step, file: []const u8, tests: []const TestPair, suite: []const u8) void {
    for (tests) |t| {
        if (std.mem.eql(u8, t.name, file)) {
            step.dependOn(&t.run.step);
            return;
        }
    }
    std.log.err("{s} test not found: {s}", .{ suite, file });
    std.process.exit(1);
}

fn runAll(
    b: *Build,
    step: *Step,
    opts: options.Options,
    lib: TestPair,
    exe: TestPair,
    integration: []const TestPair,
    conformance: []const TestPair,
) void {
    // Depend on all runs
    step.dependOn(&lib.run.step);
    step.dependOn(&exe.run.step);
    for (integration) |t| step.dependOn(&t.run.step);
    for (conformance) |t| step.dependOn(&t.run.step);

    // Build aggregation
    var artifacts = std.ArrayList(*Compile){};
    var names = std.ArrayList([]const u8){};

    artifacts.append(b.allocator, lib.compile) catch unreachable;
    names.append(b.allocator, "lib") catch unreachable;
    artifacts.append(b.allocator, exe.compile) catch unreachable;
    names.append(b.allocator, "main") catch unreachable;

    for (integration) |t| {
        artifacts.append(b.allocator, t.compile) catch unreachable;
        names.append(b.allocator, b.fmt("integration/{s}", .{t.name})) catch unreachable;
    }
    for (conformance) |t| {
        artifacts.append(b.allocator, t.compile) catch unreachable;
        names.append(b.allocator, b.fmt("conformance/{s}", .{t.name})) catch unreachable;
    }

    const agg = TestRunner.AggregateTestStep.create(b, artifacts, names, opts.test_filter, opts.fail_first, b.args);
    agg.step.dependOn(&lib.run.step);
    agg.step.dependOn(&exe.run.step);
    for (integration) |t| agg.step.dependOn(&t.run.step);
    for (conformance) |t| agg.step.dependOn(&t.run.step);
    step.dependOn(&agg.step);
}
