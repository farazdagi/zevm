//! Storage operation instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

/// Load word from storage (SLOAD).
///
/// Stack: [..., key] -> [..., value]
/// Note: This operation needs access to the storage state.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opSload(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Store word to storage (SSTORE).
///
/// Stack: [..., key, value] -> [...]
/// Note: This operation needs access to the storage state and has complex gas costs.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opSstore(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Load word from transient storage (TLOAD) - EIP-1153.
///
/// Stack: [..., key] -> [..., value]
/// Note: This operation needs access to the transient storage state.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opTload(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Store word to transient storage (TSTORE) - EIP-1153.
///
/// Stack: [..., key, value] -> [...]
/// Note: This operation needs access to the transient storage state.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opTstore(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "storage: all operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opSload(&stack));

    try stack.push(U256.fromU64(42));
    try expectError(error.UnimplementedOpcode, opSstore(&stack));

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opTload(&stack));

    try stack.push(U256.fromU64(42));
    try expectError(error.UnimplementedOpcode, opTstore(&stack));
}
