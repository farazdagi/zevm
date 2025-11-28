//! C/C++ dependency builders for crypto libraries.

const std = @import("std");
const Build = std.Build;
const Module = Build.Module;
const LazyPath = Build.LazyPath;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

/// A built C/C++ library with its module and include path.
pub const CLib = struct {
    module: ?*Module = null,
    include_path: ?LazyPath = null,
};

/// All C/C++ crypto dependencies.
pub const Deps = struct {
    secp256k1: CLib = .{},
    blst: CLib = .{},
    mcl: CLib = .{},
};

/// Build all C/C++ dependencies.
pub fn build(b: *Build, target: ResolvedTarget, optimize: OptimizeMode) Deps {
    return .{
        .secp256k1 = buildCLib(b, secp256k1_spec, target, optimize),
        .blst = buildCLib(b, blst_spec, target, optimize),
        .mcl = buildCLib(b, mcl_spec, target, optimize),
    };
}

const CLibSpec = struct {
    dep_name: []const u8,
    sources: []const []const u8,
    include_path: []const u8,
    extra_includes: []const []const u8 = &.{},
    flags: []const []const u8,
    asm_files: []const []const u8 = &.{},
    link_libcpp: bool = false,
};

const secp256k1_spec = CLibSpec{
    .dep_name = "secp256k1",
    .sources = &.{ "src/secp256k1.c", "src/precomputed_ecmult.c", "src/precomputed_ecmult_gen.c" },
    .include_path = "include",
    .extra_includes = &.{"src"},
    .flags = &.{ "-DENABLE_MODULE_RECOVERY=1", "-DECMULT_WINDOW_SIZE=15", "-DECMULT_GEN_PREC_BITS=4" },
};

const blst_spec = CLibSpec{
    .dep_name = "blst",
    .sources = &.{"src/server.c"},
    .include_path = "bindings",
    .extra_includes = &.{"src"},
    .flags = &.{"-D__BLST_PORTABLE__"},
    .asm_files = &.{"build/assembly.S"},
};

const mcl_spec = CLibSpec{
    .dep_name = "mcl",
    .sources = &.{ "src/fp.cpp", "src/bn_c256.cpp" },
    .include_path = "include",
    .extra_includes = &.{"src"},
    .flags = &.{
        "-DMCLBN_FP_UNIT_SIZE=4",      "-DMCL_DONT_USE_OPENSSL",   "-DMCL_USE_VINT",
        "-DMCL_SIZEOF_UNIT=8",         "-DMCL_VINT_FIXED_BUFFER",  "-DMCL_FP_BIT=256",
        "-DCYBOZU_DONT_USE_EXCEPTION", "-DCYBOZU_DONT_USE_STRING", "-DMCL_BINT_ASM=0",
        "-DMCL_BINT_ASM_X64=0",        "-fno-exceptions",          "-fno-rtti",
        "-std=c++11",
    },
    .link_libcpp = true,
};

fn buildCLib(b: *Build, comptime spec: CLibSpec, target: ResolvedTarget, optimize: OptimizeMode) CLib {
    const dep = b.lazyDependency(spec.dep_name, .{}) orelse return .{};

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = spec.link_libcpp,
    });

    for (spec.sources) |src| {
        mod.addCSourceFile(.{ .file = dep.path(src), .flags = spec.flags });
    }
    for (spec.asm_files) |asm_file| {
        mod.addAssemblyFile(dep.path(asm_file));
    }

    mod.addIncludePath(dep.path(spec.include_path));
    for (spec.extra_includes) |inc| {
        mod.addIncludePath(dep.path(inc));
    }

    return .{ .module = mod, .include_path = dep.path(spec.include_path) };
}
