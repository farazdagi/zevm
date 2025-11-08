const std = @import("std");
const Step = std.Build.Step;

pub const AggregateTestStep = struct {
    step: Step,
    test_artifacts: std.ArrayList(*std.Build.Step.Compile),
    test_names: std.ArrayList([]const u8),
    filter: ?[]const u8,
    fail_first: bool,
    args: ?[]const []const u8,

    const Self = @This();

    pub fn create(
        owner: *std.Build,
        test_artifacts: std.ArrayList(*std.Build.Step.Compile),
        test_names: std.ArrayList([]const u8),
        filter: ?[]const u8,
        fail_first: bool,
        args: ?[]const []const u8,
    ) *Self {
        const self = owner.allocator.create(Self) catch @panic("OOM");
        self.* = .{
            .step = Step.init(.{
                .id = .custom,
                .name = "aggregate test results",
                .owner = owner,
                .makeFn = make,
            }),
            .test_artifacts = test_artifacts,
            .test_names = test_names,
            .filter = filter,
            .fail_first = fail_first,
            .args = args,
        };
        return self;
    }

    const TestResult = struct {
        suite: []const u8,
        passed: usize,
        failed: usize,
        ignored: usize,
        leaked: usize,
        filtered: usize,
        success: bool,
    };

    fn make(step: *Step, options: Step.MakeOptions) !void {
        _ = options;
        const self: *Self = @fieldParentPtr("step", step);
        const b = step.owner;
        const allocator = b.allocator;

        var total_passed: usize = 0;
        var total_failed: usize = 0;
        var total_ignored: usize = 0;
        var total_leaked: usize = 0;
        var total_filtered: usize = 0;
        var any_failed = false;

        // Run each test artifact with --json flag and capture output
        for (self.test_artifacts.items, self.test_names.items) |artifact, name| {
            const exe_path = artifact.getEmittedBin().getPath2(b, step);

            var args = std.ArrayList([]const u8){};
            defer args.deinit(allocator);

            try args.append(allocator, exe_path);
            try args.append(allocator, "--json");
            try args.append(allocator, "--test-name");
            // Prepend "tests/" to match the format used in the first run
            const test_name = if (std.mem.startsWith(u8, name, "tests/"))
                name
            else
                try std.fmt.allocPrint(allocator, "tests/{s}", .{name});
            defer if (!std.mem.startsWith(u8, name, "tests/")) allocator.free(test_name);
            try args.append(allocator, test_name);

            if (self.filter) |f| {
                try args.append(allocator, "--filter");
                try args.append(allocator, f);
            }
            if (self.fail_first) {
                try args.append(allocator, "--fail-first");
            }

            // Add custom args if provided
            if (self.args) |custom_args| {
                for (custom_args) |arg| {
                    // Skip --json if already in custom args
                    if (!std.mem.eql(u8, arg, "--json")) {
                        try args.append(allocator, arg);
                    }
                }
            }

            // Run the test executable
            var child = std.process.Child.init(args.items, allocator);
            child.stdout_behavior = .Pipe;
            child.stderr_behavior = .Ignore;

            try child.spawn();

            // Read stdout
            const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(stdout);

            const term = try child.wait();

            // Parse JSON output
            if (std.mem.trim(u8, stdout, &std.ascii.whitespace).len > 0) {
                const result = try parseTestResult(allocator, stdout);

                total_passed += result.passed;
                total_failed += result.failed;
                total_ignored += result.ignored;
                total_leaked += result.leaked;
                total_filtered += result.filtered;

                if (!result.success) {
                    any_failed = true;
                }
            }

            // If test failed and fail_first is true, stop
            if (term != .Exited or term.Exited != 0) {
                if (self.fail_first) {
                    return error.TestsFailed;
                }
                any_failed = true;
            }
        }

        // Clear the build system's progress line (e.g., "[16/18] steps")
        // by writing escape sequences to stderr
        _ = std.posix.write(std.posix.STDERR_FILENO, "\r\x1b[2K") catch {};

        // Print aggregate summary
        var buf: [2048]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const writer = stream.writer();

        try writer.writeAll("\naggregate test result: ");
        if (!any_failed and total_failed == 0 and total_leaked == 0) {
            try writer.writeAll("\x1b[32mok\x1b[0m");
        } else {
            try writer.writeAll("\x1b[31mFAILED\x1b[0m");
        }

        try writer.print(". {d} passed; {d} failed", .{ total_passed, total_failed });
        if (total_ignored > 0) {
            try writer.print("; {d} ignored", .{total_ignored});
        }
        if (total_leaked > 0) {
            try writer.print("; {d} leaked", .{total_leaked});
        }
        if (total_filtered > 0) {
            try writer.print("; {d} filtered out", .{total_filtered});
        }
        try writer.writeAll("\n\n");

        _ = std.posix.write(std.posix.STDOUT_FILENO, stream.getWritten()) catch {};

        if (any_failed or total_failed > 0 or total_leaked > 0) {
            return error.TestsFailed;
        }
    }

    fn parseTestResult(allocator: std.mem.Allocator, json_str: []const u8) !TestResult {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_str,
            .{},
        );
        defer parsed.deinit();

        const obj = parsed.value.object;

        return TestResult{
            .suite = if (obj.get("suite")) |s| s.string else "unknown",
            .passed = if (obj.get("passed")) |p| @intCast(p.integer) else 0,
            .failed = if (obj.get("failed")) |f| @intCast(f.integer) else 0,
            .ignored = if (obj.get("ignored")) |i| @intCast(i.integer) else 0,
            .leaked = if (obj.get("leaked")) |l| @intCast(l.integer) else 0,
            .filtered = if (obj.get("filtered")) |f| @intCast(f.integer) else 0,
            .success = if (obj.get("success")) |s| s.bool else false,
        };
    }
};
