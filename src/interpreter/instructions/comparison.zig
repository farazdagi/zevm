//! Comparison instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

/// Less than (LT) - unsigned comparison.
///
/// Stack: [..., a, b] -> [..., a < b ? 1 : 0]
pub inline fn lt(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Greater than (GT) - unsigned comparison.
///
/// Stack: [..., a, b] -> [..., a > b ? 1 : 0]
pub inline fn gt(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Signed less than (SLT) - signed comparison.
///
/// Stack: [..., a, b] -> [..., a < b ? 1 : 0] (signed)
pub inline fn slt(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Signed greater than (SGT) - signed comparison.
///
/// Stack: [..., a, b] -> [..., a > b ? 1 : 0] (signed)
pub inline fn sgt(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Equality (EQ).
///
/// Stack: [..., a, b] -> [..., a == b ? 1 : 0]
pub inline fn eq(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Is zero (ISZERO).
///
/// Stack: [..., a] -> [..., a == 0 ? 1 : 0]
pub inline fn iszero(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "comparison: all operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(5));
    try stack.push(U256.fromU64(10));

    try expectError(error.UnimplementedOpcode, lt(&stack));
    try expectError(error.UnimplementedOpcode, gt(&stack));
    try expectError(error.UnimplementedOpcode, slt(&stack));
    try expectError(error.UnimplementedOpcode, sgt(&stack));
    try expectError(error.UnimplementedOpcode, eq(&stack));

    _ = try stack.pop();
    try expectError(error.UnimplementedOpcode, iszero(&stack));
}
