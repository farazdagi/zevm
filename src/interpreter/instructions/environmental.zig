//! This module contains operations that query execution environment information.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

// ============================================================================
// Transaction Context
// ============================================================================

/// Get address of currently executing account (ADDRESS).
///
/// Stack: [...] -> [..., address]
pub inline fn address(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get balance of an address (BALANCE).
///
/// Stack: [..., address] -> [..., balance]
pub inline fn balance(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get execution origination address (ORIGIN).
///
/// Stack: [...] -> [..., address]
pub inline fn origin(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get caller address (CALLER).
///
/// Stack: [...] -> [..., address]
pub inline fn caller(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get deposited value (CALLVALUE).
///
/// Stack: [...] -> [..., value]
pub inline fn callvalue(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get gas price (GASPRICE).
///
/// Stack: [...] -> [..., price]
pub inline fn gasprice(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get balance of currently executing account (SELFBALANCE) - EIP-1884.
///
/// Stack: [...] -> [..., balance]
pub inline fn selfbalance(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Calldata Operations
// ============================================================================

/// Load word from input data (CALLDATALOAD).
///
/// Stack: [..., offset] -> [..., data]
pub inline fn calldataload(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get size of input data (CALLDATASIZE).
///
/// Stack: [...] -> [..., size]
pub inline fn calldatasize(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Copy input data to memory (CALLDATACOPY).
///
/// Stack: [..., destOffset, offset, length] -> [...]
pub inline fn calldatacopy(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Code Operations
// ============================================================================

/// Get size of code (CODESIZE).
///
/// Stack: [...] -> [..., size]
pub inline fn codesize(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Copy code to memory (CODECOPY).
///
/// Stack: [..., destOffset, offset, length] -> [...]
pub inline fn codecopy(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get size of external code (EXTCODESIZE).
///
/// Stack: [..., address] -> [..., size]
pub inline fn extcodesize(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Copy external code to memory (EXTCODECOPY).
///
/// Stack: [..., address, destOffset, offset, length] -> [...]
pub inline fn extcodecopy(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get hash of external code (EXTCODEHASH) - EIP-1052.
///
/// Stack: [..., address] -> [..., hash]
pub inline fn extcodehash(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Return Data Operations
// ============================================================================

/// Get size of return data (RETURNDATASIZE) - EIP-211.
///
/// Stack: [...] -> [..., size]
pub inline fn returndatasize(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Copy return data to memory (RETURNDATACOPY) - EIP-211.
///
/// Stack: [..., destOffset, offset, length] -> [...]
pub inline fn returndatacopy(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Block Information
// ============================================================================

/// Get hash of recent complete block (BLOCKHASH).
///
/// Stack: [..., blockNumber] -> [..., hash]
pub inline fn blockhash(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's beneficiary address (COINBASE).
///
/// Stack: [...] -> [..., address]
pub inline fn coinbase(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's timestamp (TIMESTAMP).
///
/// Stack: [...] -> [..., timestamp]
pub inline fn timestamp(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's number (NUMBER).
///
/// Stack: [...] -> [..., number]
pub inline fn number(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's difficulty / PREVRANDAO (DIFFICULTY/PREVRANDAO).
///
/// Stack: [...] -> [..., difficulty]
/// Note: Post-merge this returns PREVRANDAO (EIP-4399)
pub inline fn prevrandao(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's gas limit (GASLIMIT).
///
/// Stack: [...] -> [..., limit]
pub inline fn gaslimit(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get chain ID (CHAINID) - EIP-1344.
///
/// Stack: [...] -> [..., chainId]
pub inline fn chainid(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get base fee (BASEFEE) - EIP-3198.
///
/// Stack: [...] -> [..., baseFee]
pub inline fn basefee(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get versioned hash of blob at index (BLOBHASH) - EIP-4844.
///
/// Stack: [..., index] -> [..., versionedHash]
pub inline fn blobhash(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get blob base fee (BLOBBASEFEE) - EIP-7516.
///
/// Stack: [...] -> [..., blobBaseFee]
pub inline fn blobbasefee(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "environmental: transaction context operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try expectError(error.UnimplementedOpcode, address(&stack));

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, balance(&stack));

    try expectError(error.UnimplementedOpcode, origin(&stack));
    try expectError(error.UnimplementedOpcode, caller(&stack));
    try expectError(error.UnimplementedOpcode, callvalue(&stack));
    try expectError(error.UnimplementedOpcode, gasprice(&stack));
    try expectError(error.UnimplementedOpcode, selfbalance(&stack));
}

test "environmental: calldata operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, calldataload(&stack));

    try expectError(error.UnimplementedOpcode, calldatasize(&stack));

    for (0..3) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, calldatacopy(&stack));
}

test "environmental: code operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try expectError(error.UnimplementedOpcode, codesize(&stack));

    for (0..3) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, codecopy(&stack));

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, extcodesize(&stack));

    for (0..4) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, extcodecopy(&stack));

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, extcodehash(&stack));
}

test "environmental: return data operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try expectError(error.UnimplementedOpcode, returndatasize(&stack));

    for (0..3) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, returndatacopy(&stack));
}

test "environmental: block information operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, blockhash(&stack));

    try expectError(error.UnimplementedOpcode, coinbase(&stack));
    try expectError(error.UnimplementedOpcode, timestamp(&stack));
    try expectError(error.UnimplementedOpcode, number(&stack));
    try expectError(error.UnimplementedOpcode, prevrandao(&stack));
    try expectError(error.UnimplementedOpcode, gaslimit(&stack));
    try expectError(error.UnimplementedOpcode, chainid(&stack));
    try expectError(error.UnimplementedOpcode, basefee(&stack));

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, blobhash(&stack));

    try expectError(error.UnimplementedOpcode, blobbasefee(&stack));
}
