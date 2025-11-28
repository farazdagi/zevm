//! Fixture fetcher for downloading test fixtures from GitHub.

const std = @import("std");
const sources = @import("sources.zig");

const Allocator = std.mem.Allocator;
const http = std.http;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        std.process.exit(1);
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "list")) {
        try listBundles(allocator);
    } else if (std.mem.eql(u8, command, "fetch")) {
        if (args.len < 3) {
            std.debug.print("Error: Missing bundle name\n\n", .{});
            printUsage();
            std.process.exit(1);
        }
        try fetchBundle(allocator, args[2]);
    } else {
        std.debug.print("Error: Unknown command '{s}'\n\n", .{command});
        printUsage();
        std.process.exit(1);
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: fetcher <command> [args]
        \\
        \\Commands:
        \\  list              List all bundles and their download status
        \\  fetch <bundle>    Download fixtures for a specific bundle
        \\
        \\Available bundles:
        \\
    , .{});
    for (sources.all) |source| {
        std.debug.print("  {s}: {s}\n", .{ source.name, source.description });
    }
}

// List Command
fn listBundles(allocator: Allocator) !void {
    std.debug.print("Fixture Bundles:\n\n", .{});

    for (sources.all) |source| {
        const dest_dir = source.destDir(allocator);
        defer allocator.free(dest_dir);

        const status = getDirectoryStatus(dest_dir);
        const status_str = if (status.exists) "[downloaded]" else "[missing]   ";
        const pattern_display = source.github.pattern orelse "*";

        std.debug.print("  {s} {s}", .{ status_str, source.name });
        if (status.exists) {
            std.debug.print(" ({d} files)", .{status.file_count});
        }
        std.debug.print("\n", .{});
        std.debug.print("               {s}\n", .{source.description});
        std.debug.print("               Pattern: {s} -> {s}/\n\n", .{ pattern_display, dest_dir });
    }

    std.debug.print("To download: zig build fetch-fixtures -Dbundle=NAME\n", .{});
}

const DirectoryStatus = struct {
    exists: bool,
    file_count: usize,
};

fn getDirectoryStatus(path: []const u8) DirectoryStatus {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
        return .{ .exists = false, .file_count = 0 };
    };
    defer dir.close();

    var count: usize = 0;
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
            count += 1;
        }
    }

    return .{ .exists = count > 0, .file_count = count };
}

// Fetch Command
fn fetchBundle(allocator: Allocator, bundle_name: []const u8) !void {
    const source = sources.get(bundle_name) orelse {
        std.debug.print("Error: Unknown bundle '{s}'\n\n", .{bundle_name});
        std.debug.print("Available bundles:\n", .{});
        for (sources.all) |s| {
            std.debug.print("  {s}: {s}\n", .{ s.name, s.description });
        }
        std.process.exit(1);
    };

    const dest_dir = source.destDir(allocator);
    defer allocator.free(dest_dir);

    const pattern_display = source.github.pattern orelse "*";
    std.debug.print("Fetching {s}...\n", .{source.name});
    std.debug.print("  Pattern: {s}\n", .{pattern_display});

    // Create destination directory.
    std.fs.cwd().makePath(dest_dir) catch |err| {
        std.debug.print("Error creating directory '{s}': {}\n", .{ dest_dir, err });
        std.process.exit(1);
    };

    // Fetch directory listing from GitHub API.
    var client: http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const api_url = try std.fmt.allocPrint(
        allocator,
        "https://api.github.com/repos/{s}/contents/{s}?ref={s}",
        .{ source.github.repo, source.github.path, source.github.ref },
    );
    defer allocator.free(api_url);

    std.debug.print("  Fetching file list from GitHub API...\n", .{});

    const listing_json = fetchUrl(&client, allocator, api_url) catch |err| {
        std.debug.print("Error fetching from GitHub API: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(listing_json);

    // Parse JSON and filter files.
    const files = parseAndFilterFiles(allocator, listing_json, source.github.pattern) catch |err| {
        std.debug.print("Error parsing GitHub API response: {}\n", .{err});
        std.process.exit(1);
    };
    defer {
        for (files) |f| allocator.free(f);
        allocator.free(files);
    }

    if (files.len == 0) {
        std.debug.print("  No files matching pattern '{s}' found.\n", .{pattern_display});
        return;
    }

    std.debug.print("  Found {d} files matching pattern.\n", .{files.len});

    // Download each file.
    var downloaded: usize = 0;
    for (files) |filename| {
        const raw_url = try std.fmt.allocPrint(
            allocator,
            "https://raw.githubusercontent.com/{s}/{s}/{s}/{s}",
            .{ source.github.repo, source.github.ref, source.github.path, filename },
        );
        defer allocator.free(raw_url);

        const dest_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest_dir, filename });
        defer allocator.free(dest_path);

        std.debug.print("  Downloading {s}...\n", .{filename});

        downloadFile(&client, allocator, raw_url, dest_path) catch |err| {
            std.debug.print("    Error: {}\n", .{err});
            continue;
        };
        downloaded += 1;
    }

    std.debug.print("\nDownloaded {d} files to {s}/\n", .{ downloaded, dest_dir });
}

fn fetchUrl(client: *http.Client, allocator: Allocator, url: []const u8) ![]u8 {
    const uri = try std.Uri.parse(url);

    var req = try client.request(.GET, uri, .{
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = "zevm-fixture-fetcher" },
            .{ .name = "Accept", .value = "application/vnd.github.v3+json" },
        },
    });
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buf: [8 * 1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buf);

    if (response.head.status != .ok) {
        std.debug.print("HTTP error: {}\n", .{response.head.status});
        return error.HttpError;
    }

    var transfer_buf: [16 * 1024]u8 = undefined;
    const reader = response.reader(&transfer_buf);

    return try reader.allocRemaining(allocator, .limited(10 * 1024 * 1024));
}

fn downloadFile(client: *http.Client, allocator: Allocator, url: []const u8, dest_path: []const u8) !void {
    const uri = try std.Uri.parse(url);

    var req = try client.request(.GET, uri, .{
        .extra_headers = &.{
            .{ .name = "User-Agent", .value = "zevm-fixture-fetcher" },
        },
    });
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buf: [8 * 1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buf);

    if (response.head.status != .ok) {
        return error.HttpError;
    }

    var transfer_buf: [16 * 1024]u8 = undefined;
    const reader = response.reader(&transfer_buf);

    const content = try reader.allocRemaining(allocator, .limited(100 * 1024 * 1024));
    defer allocator.free(content);

    const file = try std.fs.cwd().createFile(dest_path, .{});
    defer file.close();
    try file.writeAll(content);
}

fn parseAndFilterFiles(allocator: Allocator, json_data: []const u8, pattern: ?[]const u8) ![][]const u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // GitHub API returns an array of file objects.
    if (root != .array) {
        // Might be an error response.
        if (root == .object) {
            if (root.object.get("message")) |msg| {
                if (msg == .string) {
                    std.debug.print("GitHub API error: {s}\n", .{msg.string});
                }
            }
        }
        return error.InvalidResponse;
    }

    var files: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }

    for (root.array.items) |item| {
        if (item != .object) continue;

        // Check if it's a file (not a directory).
        const file_type = item.object.get("type") orelse continue;
        if (file_type != .string or !std.mem.eql(u8, file_type.string, "file")) continue;

        // Get the filename.
        const name_value = item.object.get("name") orelse continue;
        if (name_value != .string) continue;

        const name = name_value.string;

        // Check if it matches the pattern.
        if (matchesGlob(name, pattern)) {
            try files.append(allocator, try allocator.dupe(u8, name));
        }
    }

    return try files.toOwnedSlice(allocator);
}

/// Simple glob matching with single `*` wildcard.
/// Matches prefix before `*` and suffix after `*`.
fn matchesGlob(name: []const u8, pattern: ?[]const u8) bool {
    const pat = pattern orelse return true;
    if (std.mem.indexOfScalar(u8, pat, '*')) |star| {
        const prefix = pat[0..star];
        const suffix = pat[star + 1 ..];
        return std.mem.startsWith(u8, name, prefix) and
            std.mem.endsWith(u8, name, suffix);
    }
    // No wildcard - exact match.
    return std.mem.eql(u8, name, pat);
}
