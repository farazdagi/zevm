//! Bitwise instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

/// Bitwise AND.
///
/// Stack: [..., a, b] -> [..., a & b]
pub inline fn and_op(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Bitwise OR.
///
/// Stack: [..., a, b] -> [..., a | b]
pub inline fn or_op(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Bitwise XOR.
///
/// Stack: [..., a, b] -> [..., a ^ b]
pub inline fn xor_op(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Bitwise NOT.
///
/// Stack: [..., a] -> [..., ~a]
pub inline fn not_op(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Extract byte from word.
///
/// Stack: [..., i, x] -> [..., (x >> (248 - i * 8)) & 0xFF]
/// Returns the i-th byte of x (0 is most significant byte)
pub inline fn byte_op(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Shift left (SHL).
///
/// Stack: [..., shift, value] -> [..., value << shift]
pub inline fn shl(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Logical shift right (SHR).
///
/// Stack: [..., shift, value] -> [..., value >> shift]
/// Zero-fills on the left (logical shift)
pub inline fn shr(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Arithmetic shift right (SAR).
///
/// Stack: [..., shift, value] -> [..., value >> shift (signed)]
/// Sign-extends on the left (arithmetic shift)
pub inline fn sar(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "bitwise: all operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(0xFF));
    try stack.push(U256.fromU64(0xAA));

    try expectError(error.UnimplementedOpcode, and_op(&stack));
    try expectError(error.UnimplementedOpcode, or_op(&stack));
    try expectError(error.UnimplementedOpcode, xor_op(&stack));

    _ = try stack.pop();
    try expectError(error.UnimplementedOpcode, not_op(&stack));

    try stack.push(U256.fromU64(0));
    try expectError(error.UnimplementedOpcode, byte_op(&stack));

    try stack.push(U256.fromU64(1));
    try expectError(error.UnimplementedOpcode, shl(&stack));

    try stack.push(U256.fromU64(1));
    try expectError(error.UnimplementedOpcode, shr(&stack));

    try stack.push(U256.fromU64(1));
    try expectError(error.UnimplementedOpcode, sar(&stack));
}
