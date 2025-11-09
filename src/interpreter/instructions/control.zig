//! Control flow instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

/// Halt execution (STOP).
///
/// Note: This operation needs to set the interpreter's is_halted flag.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opStop() !void {
    return error.UnimplementedOpcode;
}

/// Jump to destination (JUMP).
///
/// Stack: [..., dest] -> [...]
/// Note: This operation needs to modify PC and validate jump destination.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opJump(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Conditional jump (JUMPI).
///
/// Stack: [..., dest, condition] -> [...]
/// Jumps to dest if condition is non-zero
/// Note: This operation needs to modify PC and validate jump destination.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opJumpi(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Jump destination marker (JUMPDEST).
///
/// This operation does nothing at runtime - it's just a marker for valid jump destinations.
pub inline fn opJumpdest() void {
    // No-op at runtime
}

/// Get program counter (PC).
///
/// Stack: [...] -> [..., pc]
/// Note: This operation needs access to the current PC value.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opPc(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get remaining gas (GAS).
///
/// Stack: [...] -> [..., gas]
/// Note: This operation needs access to the gas accounting.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opGas(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Halt execution and return data (RETURN).
///
/// Stack: [..., offset, length] -> []
/// Note: This operation needs to set return data and halt flag.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opReturn(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Halt execution and revert state changes (REVERT).
///
/// Stack: [..., offset, length] -> []
/// Note: This operation needs to set return data and revert status.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opRevert(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Invalid operation (INVALID).
///
/// This is a designated invalid instruction that consumes all remaining gas
/// and halts execution. It's used as a placeholder for undefined opcodes.
/// Note: This operation needs to consume all gas and halt.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opInvalid() !void {
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "control: JUMPDEST is a no-op" {
    opJumpdest();
    // No assertions - just verifies it compiles and runs
}

test "control: operations requiring interpreter state are unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try expectError(error.UnimplementedOpcode, opStop());

    try stack.push(U256.fromU64(10));
    try expectError(error.UnimplementedOpcode, opJump(&stack));

    try stack.push(U256.fromU64(1));
    try expectError(error.UnimplementedOpcode, opJumpi(&stack));

    try expectError(error.UnimplementedOpcode, opPc(&stack));
    try expectError(error.UnimplementedOpcode, opGas(&stack));

    try stack.push(U256.fromU64(32));
    try expectError(error.UnimplementedOpcode, opReturn(&stack));

    try stack.push(U256.fromU64(32));
    try expectError(error.UnimplementedOpcode, opRevert(&stack));

    try expectError(error.UnimplementedOpcode, opInvalid());
}
