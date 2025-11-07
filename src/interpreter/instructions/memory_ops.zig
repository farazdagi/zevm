//! Memory operation instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;
const Memory = @import("../memory.zig").Memory;

/// Load word from memory (MLOAD).
///
/// Stack: [..., offset] -> [..., value]
pub inline fn mload(stack: *Stack, memory: *Memory) !void {
    _ = stack;
    _ = memory;
    return error.UnimplementedOpcode;
}

/// Store word to memory (MSTORE).
///
/// Stack: [..., offset, value] -> [...]
pub inline fn mstore(stack: *Stack, memory: *Memory) !void {
    _ = stack;
    _ = memory;
    return error.UnimplementedOpcode;
}

/// Store byte to memory (MSTORE8).
///
/// Stack: [..., offset, value] -> [...]
/// Only the least significant byte of value is stored
pub inline fn mstore8(stack: *Stack, memory: *Memory) !void {
    _ = stack;
    _ = memory;
    return error.UnimplementedOpcode;
}

/// Get size of active memory in bytes (MSIZE).
///
/// Stack: [...] -> [..., size]
pub inline fn msize(stack: *Stack, memory: *Memory) !void {
    _ = stack;
    _ = memory;
    return error.UnimplementedOpcode;
}

/// Copy memory (MCOPY) - EIP-5656.
///
/// Stack: [..., dest_offset, src_offset, length] -> [...]
pub inline fn mcopy(stack: *Stack, memory: *Memory) !void {
    _ = stack;
    _ = memory;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "memory_ops: all operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, mload(&stack, &memory));

    try stack.push(U256.fromU64(42));
    try expectError(error.UnimplementedOpcode, mstore(&stack, &memory));

    try stack.push(U256.fromU64(0xFF));
    try expectError(error.UnimplementedOpcode, mstore8(&stack, &memory));

    try expectError(error.UnimplementedOpcode, msize(&stack, &memory));

    try stack.push(U256.fromU64(32));
    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, mcopy(&stack, &memory));
}
