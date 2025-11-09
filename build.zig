const std = @import("std");
const TestRunner = @import("libs/test-runner/build.zig");

pub fn build(b: *std.Build) !void {
    // ============================================================================
    // Build Options
    // ============================================================================

    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Test options (can be used without -- separator)
    const test_filter = b.option([]const u8, "filter", "Filter tests by name");
    const test_timing = b.option(bool, "timing", "Show timing for each test") orelse true;
    const test_fail_first = b.option(bool, "fail-first", "Stop on first test failure") orelse false;
    var test_target = b.option([]const u8, "test-target", "Run specific test target (lib, main, integration, or tests/<file>)");

    // Also check for --test-target in b.args (when using `zig build test -- --test-target=lib`)
    if (test_target == null and b.args != null) {
        for (b.args.?) |arg| {
            if (std.mem.startsWith(u8, arg, "--test-target=")) {
                test_target = arg[14..]; // Skip "--test-target=" prefix
                break;
            }
        }
    }

    // Benchmark options
    const bench_optimize = b.option(std.builtin.OptimizeMode, "bench-optimize", "Optimization mode for benchmarks") orelse .Debug;
    const bench_target = b.option([]const u8, "bench-target", "Run specific benchmark (e.g., big, stack, or bench/<file>)");

    // ============================================================================
    // Module Definition
    // ============================================================================

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("zevm", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/lib.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // ============================================================================
    // Executable
    // ============================================================================

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function.
    const exe = b.addExecutable(.{
        .name = "zevm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "zevm" is the name you will use in your source code to
                // import this module (e.g. `@import("zevm")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "zevm", .module = mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ============================================================================
    // Tests
    // ============================================================================

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
        .test_runner = .{
            .path = b.path("libs/test-runner/runner.zig"),
            .mode = .simple,
        },
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);
    TestRunner.configureRunner(run_mod_tests, test_filter, test_timing, test_fail_first, b.args);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
        .test_runner = .{
            .path = b.path("libs/test-runner/runner.zig"),
            .mode = .simple,
        },
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);
    TestRunner.configureRunner(run_exe_tests, test_filter, test_timing, test_fail_first, b.args);

    // Integration tests (`tests/` directory) - recursively auto-discover all .zig files
    const IntegrationTest = struct {
        run: *std.Build.Step.Run,
        compile: *std.Build.Step.Compile,
        file_name: []const u8, // Relative path (e.g., "big.zig" or "interpreter/stack.zig")
    };
    var integration_test_runs = std.ArrayList(IntegrationTest){};
    defer integration_test_runs.deinit(b.allocator);

    // Discover all .zig files recursively
    var test_files = try TestRunner.discoverTestFiles(b.allocator, "tests");
    defer test_files.deinit(b.allocator);
    // Note: We don't free the individual strings because they're used by integration_test_runs,
    // which persists beyond this defer. The build allocator is arena-allocated anyway.

    // Create test steps for each discovered file
    for (test_files.items) |relative_path| {
        const test_file_path = b.fmt("tests/{s}", .{relative_path});

        const integration_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file_path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zevm", .module = mod },
                },
            }),
            .test_runner = .{
                .path = b.path("libs/test-runner/runner.zig"),
                .mode = .simple,
            },
        });

        const run_integration_tests = b.addRunArtifact(integration_tests);
        TestRunner.configureRunner(run_integration_tests, test_filter, test_timing, test_fail_first, b.args);

        // Pass full path as test name for better output (e.g., "tests/interpreter/stack.zig")
        run_integration_tests.addArg("--test-name");
        run_integration_tests.addArg(test_file_path);

        try integration_test_runs.append(b.allocator, .{
            .run = run_integration_tests,
            .compile = integration_tests,
            .file_name = relative_path,
        });
    }

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");

    // Determine if we need aggregation (multiple test suites or integration tests)
    const needs_aggregation = if (test_target) |target_name|
        std.mem.eql(u8, target_name, "integration")
    else
        true; // No target = run all tests = need aggregation

    // Conditional test execution based on -Dtarget flag
    if (test_target) |target_name| {
        if (std.mem.eql(u8, target_name, "lib")) {
            test_step.dependOn(&run_mod_tests.step);
        } else if (std.mem.eql(u8, target_name, "main")) {
            test_step.dependOn(&run_exe_tests.step);
        } else if (std.mem.eql(u8, target_name, "integration")) {
            if (needs_aggregation and integration_test_runs.items.len > 0) {
                // Use aggregation for multiple integration tests
                // First, run all tests with normal output
                for (integration_test_runs.items) |integration_test| {
                    test_step.dependOn(&integration_test.run.step);
                }

                // Then add aggregation step
                var test_artifacts = std.ArrayList(*std.Build.Step.Compile){};
                var test_names = std.ArrayList([]const u8){};

                for (integration_test_runs.items) |integration_test| {
                    try test_artifacts.append(b.allocator, integration_test.compile);
                    try test_names.append(b.allocator, integration_test.file_name);
                }

                const aggregate_step = TestRunner.AggregateTestStep.create(
                    b,
                    test_artifacts,
                    test_names,
                    test_filter,
                    test_fail_first,
                    b.args,
                );

                // Aggregate step depends on all test runs completing
                for (integration_test_runs.items) |integration_test| {
                    aggregate_step.step.dependOn(&integration_test.run.step);
                }

                test_step.dependOn(&aggregate_step.step);
            } else {
                // Single or no integration tests, just run normally
                for (integration_test_runs.items) |integration_test| {
                    test_step.dependOn(&integration_test.run.step);
                }
            }
        } else if (std.mem.startsWith(u8, target_name, "tests/")) {
            // Run specific integration test file
            const test_file_name = target_name[6..]; // Skip "tests/" prefix
            var found = false;
            for (integration_test_runs.items) |integration_test| {
                if (std.mem.eql(u8, integration_test.file_name, test_file_name)) {
                    test_step.dependOn(&integration_test.run.step);
                    found = true;
                    break;
                }
            }
            if (!found) {
                std.log.err("Test file not found: {s}", .{target_name});
                std.process.exit(1);
            }
        } else {
            std.log.err("Unknown test target: {s}. Valid targets: lib, main, integration, tests/<file>", .{target_name});
            std.log.err("Usage: zig build test -Dtest-target=<target>", .{});
            std.process.exit(1);
        }
    } else {
        // No target specified, run all tests with aggregation
        // First, run all tests with normal output
        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_exe_tests.step);
        for (integration_test_runs.items) |integration_test| {
            test_step.dependOn(&integration_test.run.step);
        }

        // Then add aggregation step
        var test_artifacts = std.ArrayList(*std.Build.Step.Compile){};
        var test_names = std.ArrayList([]const u8){};

        try test_artifacts.append(b.allocator, mod_tests);
        try test_names.append(b.allocator, "lib");

        try test_artifacts.append(b.allocator, exe_tests);
        try test_names.append(b.allocator, "main");

        for (integration_test_runs.items) |integration_test| {
            try test_artifacts.append(b.allocator, integration_test.compile);
            try test_names.append(b.allocator, integration_test.file_name);
        }

        const aggregate_step = TestRunner.AggregateTestStep.create(
            b,
            test_artifacts,
            test_names,
            test_filter,
            test_fail_first,
            b.args,
        );

        // Aggregate step depends on all test runs completing
        aggregate_step.step.dependOn(&run_mod_tests.step);
        aggregate_step.step.dependOn(&run_exe_tests.step);
        for (integration_test_runs.items) |integration_test| {
            aggregate_step.step.dependOn(&integration_test.run.step);
        }

        test_step.dependOn(&aggregate_step.step);
    }

    // ============================================================================
    // Benchmarks
    // ============================================================================

    // Auto-discover benchmark files in bench/ directory
    const Benchmark = struct {
        run: *std.Build.Step.Run,
        file_name: []const u8,
    };
    var benchmark_runs = std.ArrayList(Benchmark){};
    defer benchmark_runs.deinit(b.allocator);

    // Discover benchmark files (non-recursive, top-level only)
    const bench_dir = std.fs.cwd().openDir("bench", .{ .iterate = true }) catch |err| blk: {
        if (err == error.FileNotFound) {
            break :blk null;
        }
        return err;
    };

    if (bench_dir) |dir| {
        var bench_dir_mut = dir;
        defer bench_dir_mut.close();

        var iter = bench_dir_mut.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

            const bench_file_path = b.fmt("bench/{s}", .{entry.name});

            const bench_exe = b.addExecutable(.{
                .name = b.fmt("bench-{s}", .{entry.name[0 .. entry.name.len - 4]}), // Remove .zig extension
                .root_module = b.createModule(.{
                    .root_source_file = b.path(bench_file_path),
                    .target = target,
                    .optimize = bench_optimize,
                    .imports = &.{
                        .{ .name = "zevm", .module = mod },
                    },
                }),
            });

            const run_bench = b.addRunArtifact(bench_exe);

            // Forward command-line arguments to benchmark
            if (b.args) |args| {
                run_bench.addArgs(args);
            }

            try benchmark_runs.append(b.allocator, .{
                .run = run_bench,
                .file_name = entry.name,
            });
        }
    }

    // Create top-level "bench" step
    const bench_step = b.step("bench", "Run benchmarks");

    // Conditional benchmark execution based on -Dbench-target flag
    if (bench_target) |target_name| {
        var bench_file_name: []const u8 = undefined;
        if (std.mem.startsWith(u8, target_name, "bench/")) {
            // If specified as "bench/foo.zig", extract "foo.zig"
            bench_file_name = target_name[6..];
        } else if (std.mem.endsWith(u8, target_name, ".zig")) {
            // If specified as "foo.zig", use as is
            bench_file_name = target_name;
        } else {
            // If specified as "foo", add .zig extension
            bench_file_name = b.fmt("{s}.zig", .{target_name});
        }

        var found = false;
        for (benchmark_runs.items) |benchmark| {
            if (std.mem.eql(u8, benchmark.file_name, bench_file_name)) {
                bench_step.dependOn(&benchmark.run.step);
                found = true;
                break;
            }
        }
        if (!found) {
            std.log.err("Benchmark file not found: {s}", .{bench_file_name});
            std.log.err("Available benchmarks:", .{});
            for (benchmark_runs.items) |benchmark| {
                std.log.err("  - {s}", .{benchmark.file_name[0 .. benchmark.file_name.len - 4]});
            }
            std.process.exit(1);
        }
    } else {
        // No target specified, run all benchmarks
        for (benchmark_runs.items) |benchmark| {
            bench_step.dependOn(&benchmark.run.step);
        }
    }

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
