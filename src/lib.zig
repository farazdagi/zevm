//! Main Zevm library.

const std = @import("std");
pub const primitives = @import("primitives/mod.zig");
pub const interpreter = @import("interpreter/mod.zig");
pub const hardfork = @import("hardfork.zig");
pub const gas = @import("gas/mod.zig");
pub const context = @import("context.zig");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Import tests
test {
    std.testing.refAllDecls(@This());
    _ = primitives;
    _ = interpreter;
    _ = hardfork;
    _ = gas;
    _ = context;
}
