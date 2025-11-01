// Rust-like test runner for Zig
//
// This is a custom test runner that provides output similar to Rust's test framework,
// with colored status indicators and detailed test results.
//
// Adapted from:
// - https://gist.github.com/jonathanderque/c8dbeafc68c1d45e53f629d3c78331a1
// - https://gist.github.com/karlseguin/c6bea5b35e4e8d26af6f81c22cb5d76b/1f317ebc9cd09bc50fd5591d09c34255e15d1d85

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const BORDER = "=" ** 80;

// Use in custom panic handler
var current_test: ?[]const u8 = null;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try Config.init(allocator);
    defer config.deinit(allocator);

    var slowest = SlowTracker.init(allocator, 5);
    defer slowest.deinit();

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    // Track failed tests for summary (pre-allocate for reasonable max)
    var failed_tests_buffer: [256]FailedTest = undefined;
    var failed_test_count: usize = 0;

    // Run setup functions first
    for (builtin.test_functions) |t| {
        if (isSetup(t)) {
            t.func() catch |err| {
                Printer.err("\nsetup \"{s}\" failed: {}\n", .{ t.name, err });
                return err;
            };
        }
    }

    // Count tests to run (for initial message)
    var test_count: usize = 0;
    var filtered_count: usize = 0;
    for (builtin.test_functions) |t| {
        if (isSetup(t) or isTeardown(t)) continue;

        const friendly_name = getFriendlyName(t.name);
        // Format to apply filter on the display format (with ::)
        var name_buf: [512]u8 = undefined;
        const formatted_name = formatTestName(&name_buf, friendly_name);

        if (config.filter) |f| {
            if (std.mem.indexOf(u8, formatted_name, f) == null) {
                filtered_count += 1;
                continue;
            }
        }
        test_count += 1;
    }

    // If no tests to run, exit silently
    if (test_count == 0) {
        std.posix.exit(0);
    }

    // Print header with test suite name (auto-detected or provided)
    const suite_name = config.test_name orelse blk: {
        // Auto-detect from test function names
        for (builtin.test_functions) |t| {
            if (isSetup(t) or isTeardown(t)) continue;

            var name = t.name;

            // Strip "src." prefix if present
            if (std.mem.startsWith(u8, name, "src.")) {
                name = name[4..];
            }

            // Extract root module name (e.g., "lib.test_0" -> "lib" or "main.test_0" -> "main")
            if (std.mem.indexOf(u8, name, ".")) |dot_idx| {
                break :blk name[0..dot_idx];
            }
            break :blk name;
        }
        break :blk null;
    };

    Printer.normal("\n", .{});
    if (suite_name) |name| {
        Printer.normal("running {d} test{s} ", .{ test_count, if (test_count != 1) "s" else "" });
        Printer.pass("({s})\n", .{name});
    } else {
        Printer.normal("running {d} test{s}\n", .{ test_count, if (test_count != 1) "s" else "" });
    }

    // Run tests
    for (builtin.test_functions) |t| {
        if (isSetup(t) or isTeardown(t)) {
            continue;
        }

        slowest.startTiming();

        const friendly_name = getFriendlyName(t.name);

        // Format name with :: separator for display and filtering
        var formatted_name_buf: [512]u8 = undefined;
        const formatted_name = formatTestName(&formatted_name_buf, friendly_name);

        // Apply filter to formatted name (with ::) so users can filter as they see it
        if (config.filter) |f| {
            if (std.mem.indexOf(u8, formatted_name, f) == null) {
                continue;
            }
        }

        current_test = formatted_name;

        // Print test name
        Printer.normal("test {s} ... ", .{formatted_name});

        // Run the test
        std.testing.allocator_instance = .{};
        const result = t.func();
        current_test = null;

        const ns_taken = slowest.endTiming(formatted_name);

        // Check for memory leaks
        if (std.testing.allocator_instance.deinit() == .leak) {
            leak += 1;
            Printer.leak("LEAK\n", .{});
            if (failed_test_count < failed_tests_buffer.len) {
                const err_msg = try std.fmt.allocPrint(allocator, "Memory leak detected", .{});
                failed_tests_buffer[failed_test_count] = .{
                    .name = try allocator.dupe(u8, formatted_name),
                    .error_msg = err_msg,
                };
                failed_test_count += 1;
            }
            fail += 1;
        } else if (result) |_| {
            // Test passed
            pass += 1;
            if (config.show_timing) {
                const ms = @as(f64, @floatFromInt(ns_taken)) / 1_000_000.0;
                Printer.pass("ok", .{});
                Printer.normal(" ({d:.2}ms)\n", .{ms});
            } else {
                Printer.pass("ok\n", .{});
            }
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip += 1;
                Printer.skip("ignored\n", .{});
            },
            else => {
                fail += 1;
                Printer.fail("FAILED\n", .{});

                // Store failure information
                if (failed_test_count < failed_tests_buffer.len) {
                    const err_msg = try std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)});
                    failed_tests_buffer[failed_test_count] = .{
                        .name = try allocator.dupe(u8, formatted_name),
                        .error_msg = err_msg,
                    };
                    failed_test_count += 1;
                }

                if (config.fail_first) {
                    break;
                }
            },
        }
    }

    // Run teardown functions
    for (builtin.test_functions) |t| {
        if (isTeardown(t)) {
            t.func() catch |err| {
                Printer.err("\nteardown \"{s}\" failed: {}\n", .{ t.name, err });
                return err;
            };
        }
    }

    // Print failures section
    if (failed_test_count > 0) {
        Printer.normal("\n", .{});
        Printer.fail("failures:\n\n", .{});
        for (failed_tests_buffer[0..failed_test_count]) |ft| {
            Printer.normal("---- {s} ----\n", .{ft.name});
            Printer.err("{s}\n\n", .{ft.error_msg});
        }
    }

    // Print slowest tests
    if (pass + fail > 0) {
        Printer.normal("\n", .{});
        try slowest.display();
    }

    // Print summary
    Printer.normal("\ntest result: ", .{});
    if (fail == 0 and leak == 0) {
        Printer.pass("ok", .{});
    } else {
        Printer.fail("FAILED", .{});
    }

    Printer.normal(". {d} passed; {d} failed", .{ pass, fail });
    if (skip > 0) {
        Printer.normal("; {d} ignored", .{skip});
    }
    if (leak > 0) {
        Printer.normal("; {d} leaked", .{leak});
    }
    if (filtered_count > 0) {
        Printer.normal("; {d} filtered out", .{filtered_count});
    }
    Printer.normal("\n\n", .{});

    // Clean up failed test data
    for (failed_tests_buffer[0..failed_test_count]) |ft| {
        allocator.free(ft.name);
        allocator.free(ft.error_msg);
    }

    std.posix.exit(if (fail == 0 and leak == 0) 0 else 1);
}

const FailedTest = struct {
    name: []const u8,
    error_msg: []const u8,
};

const Printer = struct {
    fn print(comptime format: []const u8, args: anytype) void {
        var buf: [4096]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, format, args) catch return;
        _ = std.posix.write(std.posix.STDOUT_FILENO, msg) catch {};
    }

    fn normal(comptime format: []const u8, args: anytype) void {
        print(format, args);
    }

    fn pass(comptime format: []const u8, args: anytype) void {
        print("\x1b[32m" ++ format ++ "\x1b[0m", args);
    }

    fn fail(comptime format: []const u8, args: anytype) void {
        print("\x1b[31m" ++ format ++ "\x1b[0m", args);
    }

    fn skip(comptime format: []const u8, args: anytype) void {
        print("\x1b[33m" ++ format ++ "\x1b[0m", args);
    }

    fn leak(comptime format: []const u8, args: anytype) void {
        print("\x1b[35m" ++ format ++ "\x1b[0m", args);
    }

    fn err(comptime format: []const u8, args: anytype) void {
        print("\x1b[31m" ++ format ++ "\x1b[0m", args);
    }
};

const SlowTracker = struct {
    const SlowestQueue = std.PriorityDequeue(TestInfo, void, compareTiming);
    max: usize,
    slowest: SlowestQueue,
    timer: std.time.Timer,
    allocator: Allocator,

    fn init(allocator: Allocator, count: u32) SlowTracker {
        const timer = std.time.Timer.start() catch @panic("failed to start timer");
        var slowest = SlowestQueue.init(allocator, {});
        slowest.ensureTotalCapacity(count) catch @panic("OOM");
        return .{
            .max = count,
            .timer = timer,
            .slowest = slowest,
            .allocator = allocator,
        };
    }

    const TestInfo = struct {
        ns: u64,
        name: [512]u8, // Fixed buffer to store the name
        name_len: usize,
    };

    fn deinit(self: SlowTracker) void {
        self.slowest.deinit();
    }

    fn startTiming(self: *SlowTracker) void {
        self.timer.reset();
    }

    fn endTiming(self: *SlowTracker, test_name: []const u8) u64 {
        var timer = self.timer;
        const ns = timer.lap();

        var slowest = &self.slowest;

        // Create TestInfo with copied name
        var info: TestInfo = undefined;
        info.ns = ns;
        const copy_len = @min(test_name.len, info.name.len);
        @memcpy(info.name[0..copy_len], test_name[0..copy_len]);
        info.name_len = copy_len;

        if (slowest.count() < self.max) {
            slowest.add(info) catch @panic("failed to track test timing");
            return ns;
        }

        {
            const fastest_of_the_slow = slowest.peekMin() orelse unreachable;
            if (fastest_of_the_slow.ns > ns) {
                return ns;
            }
        }

        _ = slowest.removeMin();
        slowest.add(info) catch @panic("failed to track test timing");
        return ns;
    }

    fn display(self: *SlowTracker) !void {
        var slowest = self.slowest;
        const count = slowest.count();
        if (count == 0) return;

        // Threshold: 1 second = 1_000_000_000 nanoseconds
        const threshold_ns: u64 = 1_000_000_000;

        // Collect all items into a fixed buffer
        var items: [16]TestInfo = undefined;
        var item_count: usize = 0;

        while (slowest.removeMinOrNull()) |info| {
            if (item_count < items.len) {
                items[item_count] = info;
                item_count += 1;
            }
        }

        // Check if any test exceeds the threshold
        var has_slow_test = false;
        for (items[0..item_count]) |info| {
            if (info.ns >= threshold_ns) {
                has_slow_test = true;
                break;
            }
        }

        // Only display if at least one test exceeded the threshold
        if (!has_slow_test) return;

        // Count how many tests exceeded the threshold
        var slow_count: usize = 0;
        for (items[0..item_count]) |info| {
            if (info.ns >= threshold_ns) {
                slow_count += 1;
            }
        }

        Printer.normal("slowest {d} test{s} (exceeding 1s threshold):\n", .{ slow_count, if (slow_count != 1) "s" else "" });

        // Print in reverse order (slowest first), only tests exceeding threshold
        var i = item_count;
        while (i > 0) {
            i -= 1;
            const info = items[i];
            if (info.ns >= threshold_ns) {
                const ms = @as(f64, @floatFromInt(info.ns)) / 1_000_000.0;
                const name_slice = info.name[0..info.name_len];
                Printer.normal("  {d:>8.2}ms  {s}\n", .{ ms, name_slice });
            }
        }
    }

    fn compareTiming(context: void, a: TestInfo, b: TestInfo) std.math.Order {
        _ = context;
        return std.math.order(a.ns, b.ns);
    }
};

const Config = struct {
    filter: ?[]const u8,
    fail_first: bool,
    show_timing: bool,
    test_name: ?[]const u8,
    owns_filter: bool, // Track if we need to free filter
    owns_test_name: bool,

    fn init(allocator: Allocator) !Config {
        // First, try to parse command-line arguments
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        // Skip the first argument (program name)
        _ = args.next();

        var filter: ?[]const u8 = null;
        var fail_first: ?bool = null;
        var show_timing: ?bool = null;
        var test_name: ?[]const u8 = null;
        var owns_filter = false;
        var owns_test_name = false;

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--fail-first")) {
                fail_first = true;
            } else if (std.mem.eql(u8, arg, "--timing")) {
                show_timing = true;
            } else if (std.mem.startsWith(u8, arg, "--filter=")) {
                if (filter == null) {
                    filter = try allocator.dupe(u8, arg["--filter=".len..]);
                    owns_filter = true;
                }
            } else if (std.mem.eql(u8, arg, "--filter")) {
                // Next arg should be the filter value
                if (args.next()) |filter_val| {
                    if (filter == null) {
                        filter = try allocator.dupe(u8, filter_val);
                        owns_filter = true;
                    }
                }
            } else if (std.mem.eql(u8, arg, "--test-name")) {
                // Next arg should be the test suite name
                if (args.next()) |name_val| {
                    if (test_name == null) {
                        test_name = try allocator.dupe(u8, name_val);
                        owns_test_name = true;
                    }
                }
            } else if (filter == null and !std.mem.startsWith(u8, arg, "--")) {
                // Positional argument - treat as filter
                filter = try allocator.dupe(u8, arg);
                owns_filter = true;
            }
        }

        // Fall back to environment variables if not set via CLI
        if (filter == null) {
            filter = readEnv(allocator, "TEST_FILTER");
            owns_filter = filter != null;
        }
        if (fail_first == null) {
            fail_first = readEnvBool(allocator, "TEST_FAIL_FIRST", false);
        }
        if (show_timing == null) {
            show_timing = readEnvBool(allocator, "TEST_TIMING", false);
        }

        return .{
            .filter = filter,
            .fail_first = fail_first orelse false,
            .show_timing = show_timing orelse false,
            .test_name = test_name,
            .owns_filter = owns_filter,
            .owns_test_name = owns_test_name,
        };
    }

    fn deinit(self: Config, allocator: Allocator) void {
        if (self.owns_filter) {
            if (self.filter) |f| {
                allocator.free(f);
            }
        }
        if (self.owns_test_name) {
            if (self.test_name) |n| {
                allocator.free(n);
            }
        }
    }

    fn readEnv(allocator: Allocator, key: []const u8) ?[]const u8 {
        const v = std.process.getEnvVarOwned(allocator, key) catch |err| {
            if (err == error.EnvironmentVariableNotFound) {
                return null;
            }
            std.log.warn("failed to get env var {s} due to err {}", .{ key, err });
            return null;
        };
        return v;
    }

    fn readEnvBool(allocator: Allocator, key: []const u8, default: bool) bool {
        const value = readEnv(allocator, key) orelse return default;
        defer allocator.free(value);
        return std.ascii.eqlIgnoreCase(value, "true");
    }
};

pub const panic = std.debug.FullPanic(struct {
    pub fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
        if (current_test) |ct| {
            std.debug.print("\x1b[31m\n{s}\npanic in test \"{s}\": {s}\n{s}\x1b[0m\n", .{ BORDER, ct, msg, BORDER });
        }
        std.debug.defaultPanic(msg, first_trace_addr);
    }
}.panicFn);

fn isUnnamed(t: std.builtin.TestFn) bool {
    const marker = ".test_";
    const test_name = t.name;
    const index = std.mem.indexOf(u8, test_name, marker) orelse return false;
    _ = std.fmt.parseInt(u32, test_name[index + marker.len ..], 10) catch return false;
    return true;
}

fn isSetup(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:beforeAll");
}

fn isTeardown(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:afterAll");
}

fn getFriendlyName(full_name: []const u8) []const u8 {
    // Strip "src." prefix if present to show relative path from src/
    var name = full_name;
    if (std.mem.startsWith(u8, name, "src.")) {
        name = name[4..];
    }
    return name;
}

fn formatTestName(buf: []u8, name: []const u8) []const u8 {
    // Replace ".test." with "::" and ".test_" with "::"
    // e.g., "lib.test.my_test" -> "lib::my_test"
    // e.g., "primitives.address.test.my_test" -> "primitives.address::my_test"
    // e.g., "lib.test_0" -> "lib::test_0"

    if (std.mem.indexOf(u8, name, ".test.")) |idx| {
        // Found ".test." - replace with "::"
        const module_path = name[0..idx];
        const test_name = name[idx + 6 ..]; // Skip ".test."
        const formatted = std.fmt.bufPrint(buf, "{s}::{s}", .{ module_path, test_name }) catch name;
        return formatted;
    } else if (std.mem.indexOf(u8, name, ".test_")) |idx| {
        // Found ".test_" (numbered test) - replace with "::"
        const module_path = name[0..idx];
        const test_name = name[idx + 1 ..]; // Skip "."
        const formatted = std.fmt.bufPrint(buf, "{s}::{s}", .{ module_path, test_name }) catch name;
        return formatted;
    }

    return name;
}
