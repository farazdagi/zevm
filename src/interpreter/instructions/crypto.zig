//! Crypto instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;
const Memory = @import("../memory.zig").Memory;

/// Compute Keccak-256 hash (KECCAK256).
///
/// Stack: [..., offset, length] -> [..., hash]
/// Reads data from memory and pushes the keccak256 hash onto the stack.
/// Note: This operation requires access to memory and has dynamic gas costs.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn keccak256(stack: *Stack, memory: *Memory) !void {
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

test "crypto: KECCAK256 unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try stack.push(U256.fromU64(32)); // length
    try stack.push(U256.ZERO); // offset
    try expectError(error.UnimplementedOpcode, keccak256(&stack, &memory));
}
