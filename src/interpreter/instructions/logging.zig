//! Logging instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

/// Emit log with 0 topics (LOG0).
///
/// Stack: [..., offset, length] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opLog0(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Emit log with 1 topic (LOG1).
///
/// Stack: [..., offset, length, topic1] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opLog1(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Emit log with 2 topics (LOG2).
///
/// Stack: [..., offset, length, topic1, topic2] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opLog2(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Emit log with 3 topics (LOG3).
///
/// Stack: [..., offset, length, topic1, topic2, topic3] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opLog3(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Emit log with 4 topics (LOG4).
///
/// Stack: [..., offset, length, topic1, topic2, topic3, topic4] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opLog4(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "logging: all operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    // LOG0
    try stack.push(U256.fromU64(32)); // length
    try stack.push(U256.ZERO); // offset
    try expectError(error.UnimplementedOpcode, opLog0(&stack));

    // LOG1
    try stack.push(U256.fromU64(32)); // length
    try stack.push(U256.ZERO); // offset
    try stack.push(U256.ZERO); // topic1
    try expectError(error.UnimplementedOpcode, opLog1(&stack));

    // LOG2
    for (0..4) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opLog2(&stack));

    // LOG3
    for (0..5) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opLog3(&stack));

    // LOG4
    for (0..6) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opLog4(&stack));
}
