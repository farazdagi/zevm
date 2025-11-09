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
pub inline fn opAddress(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get balance of an address (BALANCE).
///
/// Stack: [..., address] -> [..., balance]
pub inline fn opBalance(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get execution origination address (ORIGIN).
///
/// Stack: [...] -> [..., address]
pub inline fn opOrigin(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get caller address (CALLER).
///
/// Stack: [...] -> [..., address]
pub inline fn opCaller(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get deposited value (CALLVALUE).
///
/// Stack: [...] -> [..., value]
pub inline fn opCallvalue(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get gas price (GASPRICE).
///
/// Stack: [...] -> [..., price]
pub inline fn opGasprice(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get balance of currently executing account (SELFBALANCE) - EIP-1884.
///
/// Stack: [...] -> [..., balance]
pub inline fn opSelfbalance(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Calldata Operations
// ============================================================================

/// Load word from input data (CALLDATALOAD).
///
/// Stack: [..., offset] -> [..., data]
pub inline fn opCalldataload(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get size of input data (CALLDATASIZE).
///
/// Stack: [...] -> [..., size]
pub inline fn opCalldatasize(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Copy input data to memory (CALLDATACOPY).
///
/// Stack: [..., destOffset, offset, length] -> [...]
pub inline fn opCalldatacopy(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Code Operations
// ============================================================================

/// Get size of code (CODESIZE).
///
/// Stack: [...] -> [..., size]
pub inline fn opCodesize(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Copy code to memory (CODECOPY).
///
/// Stack: [..., destOffset, offset, length] -> [...]
pub inline fn opCodecopy(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get size of external code (EXTCODESIZE).
///
/// Stack: [..., address] -> [..., size]
pub inline fn opExtcodesize(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Copy external code to memory (EXTCODECOPY).
///
/// Stack: [..., address, destOffset, offset, length] -> [...]
pub inline fn opExtcodecopy(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get hash of external code (EXTCODEHASH) - EIP-1052.
///
/// Stack: [..., address] -> [..., hash]
pub inline fn opExtcodehash(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Return Data Operations
// ============================================================================

/// Get size of return data (RETURNDATASIZE) - EIP-211.
///
/// Stack: [...] -> [..., size]
pub inline fn opReturndatasize(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Copy return data to memory (RETURNDATACOPY) - EIP-211.
///
/// Stack: [..., destOffset, offset, length] -> [...]
pub inline fn opReturndatacopy(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Block Information
// ============================================================================

/// Get hash of recent complete block (BLOCKHASH).
///
/// Stack: [..., blockNumber] -> [..., hash]
pub inline fn opBlockhash(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's beneficiary address (COINBASE).
///
/// Stack: [...] -> [..., address]
pub inline fn opCoinbase(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's timestamp (TIMESTAMP).
///
/// Stack: [...] -> [..., timestamp]
pub inline fn opTimestamp(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's number (NUMBER).
///
/// Stack: [...] -> [..., number]
pub inline fn opNumber(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's difficulty / PREVRANDAO (DIFFICULTY/PREVRANDAO).
///
/// Stack: [...] -> [..., difficulty]
/// Note: Post-merge this returns PREVRANDAO (EIP-4399)
pub inline fn opPrevrandao(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get block's gas limit (GASLIMIT).
///
/// Stack: [...] -> [..., limit]
pub inline fn opGaslimit(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get chain ID (CHAINID) - EIP-1344.
///
/// Stack: [...] -> [..., chainId]
pub inline fn opChainid(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get base fee (BASEFEE) - EIP-3198.
///
/// Stack: [...] -> [..., baseFee]
pub inline fn opBasefee(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get versioned hash of blob at index (BLOBHASH) - EIP-4844.
///
/// Stack: [..., index] -> [..., versionedHash]
pub inline fn opBlobhash(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
}

/// Get blob base fee (BLOBBASEFEE) - EIP-7516.
///
/// Stack: [...] -> [..., blobBaseFee]
pub inline fn opBlobbasefee(stack: *Stack) !void {
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

    try expectError(error.UnimplementedOpcode, opAddress(&stack));

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opBalance(&stack));

    try expectError(error.UnimplementedOpcode, opOrigin(&stack));
    try expectError(error.UnimplementedOpcode, opCaller(&stack));
    try expectError(error.UnimplementedOpcode, opCallvalue(&stack));
    try expectError(error.UnimplementedOpcode, opGasprice(&stack));
    try expectError(error.UnimplementedOpcode, opSelfbalance(&stack));
}

test "environmental: calldata operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opCalldataload(&stack));

    try expectError(error.UnimplementedOpcode, opCalldatasize(&stack));

    for (0..3) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opCalldatacopy(&stack));
}

test "environmental: code operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try expectError(error.UnimplementedOpcode, opCodesize(&stack));

    for (0..3) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opCodecopy(&stack));

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opExtcodesize(&stack));

    for (0..4) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opExtcodecopy(&stack));

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opExtcodehash(&stack));
}

test "environmental: return data operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try expectError(error.UnimplementedOpcode, opReturndatasize(&stack));

    for (0..3) |_| try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opReturndatacopy(&stack));
}

test "environmental: block information operations unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opBlockhash(&stack));

    try expectError(error.UnimplementedOpcode, opCoinbase(&stack));
    try expectError(error.UnimplementedOpcode, opTimestamp(&stack));
    try expectError(error.UnimplementedOpcode, opNumber(&stack));
    try expectError(error.UnimplementedOpcode, opPrevrandao(&stack));
    try expectError(error.UnimplementedOpcode, opGaslimit(&stack));
    try expectError(error.UnimplementedOpcode, opChainid(&stack));
    try expectError(error.UnimplementedOpcode, opBasefee(&stack));

    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opBlobhash(&stack));

    try expectError(error.UnimplementedOpcode, opBlobbasefee(&stack));
}
