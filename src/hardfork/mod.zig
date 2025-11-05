const std = @import("std");

pub const spec = @import("spec.zig");

// Re-exports
pub const Hardfork = spec.Hardfork;
pub const Spec = spec.Spec;

test {
    std.testing.refAllDecls(@This());
}
