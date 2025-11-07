const std = @import("std");

pub const AggregateTestStep = @import("aggregate_step.zig").AggregateTestStep;

/// Discovers all .zig files recursively in a directory.
/// Returns an ArrayList of relative paths (e.g., "big.zig", "interpreter/stack.zig").
pub fn discoverTestFiles(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
) !std.ArrayList([]const u8) {
    var files = std.ArrayList([]const u8){};
    errdefer {
        for (files.items) |file| allocator.free(file);
        files.deinit(allocator);
    }
    try discoverZigFilesRecursive(allocator, dir_path, "", &files);
    return files;
}

/// Helper function to recursively discover .zig files in a directory.
fn discoverZigFilesRecursive(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    relative_path: []const u8,
    files: *std.ArrayList([]const u8),
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Compute the relative path for this entry
        const entry_relative_path = if (relative_path.len == 0)
            try allocator.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ relative_path, entry.name });

        const entry_full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
        defer allocator.free(entry_full_path);

        if (entry.kind == .directory) {
            // Recursively process subdirectory
            try discoverZigFilesRecursive(allocator, entry_full_path, entry_relative_path, files);
        } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            // Add .zig file to the list
            try files.append(allocator, entry_relative_path);
        } else {
            // Not a .zig file, free the allocated path
            allocator.free(entry_relative_path);
        }
    }
}

/// Configures a test runner with common options (filter, timing, fail-first, args).
pub fn configureRunner(
    run: *std.Build.Step.Run,
    filter: ?[]const u8,
    timing: bool,
    fail_first: bool,
    args: ?[]const []const u8,
) void {
    if (filter) |f| {
        run.addArg("--filter");
        run.addArg(f);
    }
    if (timing) {
        run.addArg("--timing");
    }
    if (fail_first) {
        run.addArg("--fail-first");
    }
    if (args) |a| {
        run.addArgs(a);
    }
}
