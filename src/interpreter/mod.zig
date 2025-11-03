const std = @import("std");

pub const stack = @import("stack.zig");

// Re-exports
pub const Stack = stack.Stack;

test {
    std.testing.refAllDecls(@This());
}
