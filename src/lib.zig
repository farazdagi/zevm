//! Main Zevm library.

const std = @import("std");
const primitives = @import("primitives/mod.zig");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Import tests
test {
    std.testing.refAllDecls(@This());
    _ = primitives;
}
