//! Build system module for managing external test fixtures.
//!
//! Provides two build steps:
//! `fetch-fixtures`: Download fixtures for a specific bundle
//! `list-fixtures`: List all available fixture bundles and their status

const std = @import("std");

/// Set up fixture-related build steps.
pub fn setup(b: *std.Build) void {
    // Compile the fetcher tool.
    const fetcher = b.addExecutable(.{
        .name = "fetcher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/fetcher.zig"),
            .target = b.graph.host,
        }),
    });

    // Step: fetch-fixtures -Dbundle=NAME
    const fetch_step = b.step("fetch-fixtures", "Download external test fixtures (-Dbundle=NAME)");
    const bundle = b.option([]const u8, "bundle", "Fixture bundle to fetch (e.g., geth-precompiles)");

    if (bundle) |name| {
        const fetch_run = b.addRunArtifact(fetcher);
        fetch_run.addArg("fetch");
        fetch_run.addArg(name);
        fetch_step.dependOn(&fetch_run.step);
    } else {
        // No bundle specified - just run without args to show usage.
        const usage_run = b.addRunArtifact(fetcher);
        fetch_step.dependOn(&usage_run.step);
    }

    // Step: list-fixtures
    const list_step = b.step("list-fixtures", "List available fixture bundles and download status");
    const list_run = b.addRunArtifact(fetcher);
    list_run.addArg("list");
    list_step.dependOn(&list_run.step);
}
