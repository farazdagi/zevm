const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Test runner options (can be used without -- separator)
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

    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

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

    // Pass build options to test runner (e.g., -Dfilter=address)
    if (test_filter) |filter| {
        run_mod_tests.addArg("--filter");
        run_mod_tests.addArg(filter);
    }
    if (test_timing) {
        run_mod_tests.addArg("--timing");
    }
    if (test_fail_first) {
        run_mod_tests.addArg("--fail-first");
    }

    // Also forward any direct command-line arguments (e.g., zig build test -- --filter address)
    if (b.args) |args| {
        run_mod_tests.addArgs(args);
    }

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

    // Pass build options to test runner
    if (test_filter) |filter| {
        run_exe_tests.addArg("--filter");
        run_exe_tests.addArg(filter);
    }
    if (test_timing) {
        run_exe_tests.addArg("--timing");
    }
    if (test_fail_first) {
        run_exe_tests.addArg("--fail-first");
    }

    // Also forward any direct command-line arguments
    if (b.args) |args| {
        run_exe_tests.addArgs(args);
    }

    // Integration tests (`tests/` directory) - auto-discover all .zig files
    const IntegrationTest = struct {
        run: *std.Build.Step.Run,
        file_name: []const u8,
    };
    var integration_test_runs = std.ArrayList(IntegrationTest){};
    defer integration_test_runs.deinit(b.allocator);

    const tests_dir = std.fs.cwd().openDir("tests", .{
        .iterate = true,
    }) catch |err| blk: {
        if (err == error.FileNotFound) {
            // No tests directory, skip integration tests
            break :blk null;
        }
        return err;
    };

    if (tests_dir) |dir| {
        var tests_dir_mut = dir;
        defer tests_dir_mut.close();

        var iter = tests_dir_mut.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

            const test_file_path = b.fmt("tests/{s}", .{entry.name});

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

            // Pass build options to test runner
            if (test_filter) |filter| {
                run_integration_tests.addArg("--filter");
                run_integration_tests.addArg(filter);
            }
            if (test_timing) {
                run_integration_tests.addArg("--timing");
            }
            if (test_fail_first) {
                run_integration_tests.addArg("--fail-first");
            }

            // Also forward any direct command-line arguments
            if (b.args) |args| {
                run_integration_tests.addArgs(args);
            }

            try integration_test_runs.append(b.allocator, .{
                .run = run_integration_tests,
                .file_name = entry.name,
            });
        }
    }

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");

    // Conditional test execution based on -Dtarget flag
    if (test_target) |target_name| {
        if (std.mem.eql(u8, target_name, "lib")) {
            test_step.dependOn(&run_mod_tests.step);
        } else if (std.mem.eql(u8, target_name, "main")) {
            test_step.dependOn(&run_exe_tests.step);
        } else if (std.mem.eql(u8, target_name, "integration")) {
            // Run all integration tests
            for (integration_test_runs.items) |integration_test| {
                test_step.dependOn(&integration_test.run.step);
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
        // No target specified, run all tests (default behavior)
        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_exe_tests.step);
        for (integration_test_runs.items) |integration_test| {
            test_step.dependOn(&integration_test.run.step);
        }
    }

    // Benchmark optimization level
    // Default to Debug to prevent over-optimization of benchmark loops
    // Use -Dbench-optimize=ReleaseFast to test with full optimizations
    const bench_optimize = b.option(std.builtin.OptimizeMode, "bench-optimize", "Optimization mode for benchmarks") orelse .Debug;

    // Create benchmark executable
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/big.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{
                .{ .name = "zevm", .module = mod },
            },
        }),
    });

    // Create run step for benchmarks
    const run_bench = b.addRunArtifact(bench_exe);

    // Forward command-line arguments to benchmark
    if (b.args) |args| {
        run_bench.addArgs(args);
    }

    // Create top-level "bench" step
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
