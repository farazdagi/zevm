//! System operation instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

/// Create a new contract (CREATE).
///
/// Stack: [..., value, offset, length] -> [..., address]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opCreate(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Create a new contract with deterministic address (CREATE2) - EIP-1014.
///
/// Stack: [..., value, offset, length, salt] -> [..., address]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opCreate2(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Call another contract (CALL).
///
/// Stack: [..., gas, address, value, argsOffset, argsLength, retOffset, retLength] -> [..., success]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opCall(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Call another contract's code in current context (CALLCODE).
///
/// Stack: [..., gas, address, value, argsOffset, argsLength, retOffset, retLength] -> [..., success]
/// Note: Deprecated in favor of DELEGATECALL.
/// This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opCallcode(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Call another contract's code in current context (DELEGATECALL) - EIP-7.
///
/// Stack: [..., gas, address, argsOffset, argsLength, retOffset, retLength] -> [..., success]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opDelegatecall(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Static call to another contract (STATICCALL) - EIP-214.
///
/// Stack: [..., gas, address, argsOffset, argsLength, retOffset, retLength] -> [..., success]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opStaticcall(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Destroy contract and send funds (SELFDESTRUCT).
///
/// Stack: [..., address] -> []
/// Note: This operation requires state modifications and special handling.
/// It will be handled specially in the interpreter's execute() function.
pub inline fn opSelfdestruct(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "system: all operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    // CREATE
    try stack.push(U256.fromU64(32)); // length
    try stack.push(U256.ZERO); // offset
    try stack.push(U256.ZERO); // value
    try expectError(error.UnimplementedOpcode, opCreate(&stack));

    // CREATE2
    try stack.push(U256.ZERO); // salt
    try stack.push(U256.fromU64(32)); // length
    try stack.push(U256.ZERO); // offset
    try stack.push(U256.ZERO); // value
    try expectError(error.UnimplementedOpcode, opCreate2(&stack));

    // CALL
    for (0..7) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opCall(&stack));

    // CALLCODE
    for (0..7) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opCallcode(&stack));

    // DELEGATECALL
    for (0..6) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opDelegatecall(&stack));

    // STATICCALL
    for (0..6) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opStaticcall(&stack));

    // SELFDESTRUCT
    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opSelfdestruct(&stack));
}
