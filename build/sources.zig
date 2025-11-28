//! Fixture source definitions for conformance testing.

const std = @import("std");

/// GitHub repository source configuration.
pub const GithubSource = struct {
    /// Repository in "owner/repo" format.
    repo: []const u8,
    /// Git ref (tag, branch, or commit SHA).
    ref: []const u8,
    /// Path within repository.
    path: []const u8,
    /// Glob pattern to filter files (null = all files).
    /// Supports: *.json, testcases_*.json, etc.
    pattern: ?[]const u8,
};

/// A fixture source definition.
pub const Source = struct {
    /// Unique bundle identifier (used in -Dbundle=NAME).
    name: []const u8,
    /// Human-readable description.
    description: []const u8,
    /// Destination folder name (relative to tests/conformance/fixtures/).
    dest: []const u8,
    /// GitHub repository source configuration.
    github: GithubSource,

    /// Returns the destination directory for this source's fixtures.
    pub fn destDir(self: Source, allocator: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(allocator, "tests/conformance/fixtures/{s}", .{self.dest}) catch unreachable;
    }
};

/// All available fixture sources.
pub const all = [_]Source{
    .{
        .name = "geth-precompiles",
        .description = "go-ethereum precompile test vectors (v1.14.0)",
        .dest = "geth-precompiles",
        .github = .{
            .repo = "ethereum/go-ethereum",
            .ref = "v1.14.0",
            .path = "core/vm/testdata/precompiles",
            .pattern = "*.json",
        },
    },
    .{
        .name = "geth-opcodes",
        .description = "go-ethereum opcode test vectors (v1.14.0)",
        .dest = "geth-opcodes",
        .github = .{
            .repo = "ethereum/go-ethereum",
            .ref = "v1.14.0",
            .path = "core/vm/testdata",
            .pattern = "testcases_*.json",
        },
    },
};

/// Look up a source by name.
pub fn get(name: []const u8) ?Source {
    for (all) |source| {
        if (std.mem.eql(u8, source.name, name)) return source;
    }
    return null;
}

/// Get all available source names for display.
pub fn names() []const []const u8 {
    comptime {
        var result: [all.len][]const u8 = undefined;
        for (all, 0..) |source, i| {
            result[i] = source.name;
        }
        return &result;
    }
}
