//! Creates the main zevm module and all crypto wrapper modules.

const std = @import("std");
const deps = @import("deps.zig");

const Build = std.Build;
const Module = Build.Module;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

/// Create the main zevm module with all crypto dependencies.
pub fn createZevmModule(b: *Build, d: deps.Deps, target: ResolvedTarget, optimize: OptimizeMode) *Module {
    const secp256k1 = createWrapper(b, "secp256k1", "libs/secp256k1/secp256k1.zig", d.secp256k1, target, optimize, false);
    const mcl = createWrapper(b, "mcl", "libs/mcl/mcl.zig", d.mcl, target, optimize, true);
    const blst = createWrapper(b, "blst", "libs/blst/blst.zig", d.blst, target, optimize, false);

    // bn254 depends on mcl
    const bn254 = b.addModule("bn254", .{
        .root_source_file = b.path("libs/bn254/bn254.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = d.mcl.module != null,
        .link_libcpp = d.mcl.module != null,
        .imports = &.{.{ .name = "mcl", .module = mcl }},
    });

    return b.addModule("zevm", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "secp256k1", .module = secp256k1 },
            .{ .name = "bn254", .module = bn254 },
            .{ .name = "blst", .module = blst },
        },
    });
}

/// Create a Zig wrapper module for a C/C++ library.
fn createWrapper(
    b: *Build,
    comptime name: []const u8,
    source: []const u8,
    c_lib: deps.CLib,
    target: ResolvedTarget,
    optimize: OptimizeMode,
    link_libcpp: bool,
) *Module {
    const has_c = c_lib.module != null;
    const mod = b.addModule(name, .{
        .root_source_file = b.path(source),
        .target = target,
        .optimize = optimize,
        .link_libc = has_c,
        .link_libcpp = has_c and link_libcpp,
    });
    if (c_lib.module) |c| mod.addImport(name ++ "_c", c);
    if (c_lib.include_path) |p| mod.addIncludePath(p);
    return mod;
}
