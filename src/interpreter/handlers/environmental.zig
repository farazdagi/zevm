//! This module contains operations that query execution environment information.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;

// ============================================================================
// Transaction Context
// ============================================================================

/// Get address of currently executing account (ADDRESS).
///
/// Stack: [...] -> [..., address]
pub fn opAddress(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get balance of an address (BALANCE).
///
/// Stack: [..., address] -> [..., balance]
pub fn opBalance(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get execution origination address (ORIGIN).
///
/// Stack: [...] -> [..., address]
pub fn opOrigin(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get caller address (CALLER).
///
/// Stack: [...] -> [..., address]
pub fn opCaller(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get deposited value (CALLVALUE).
///
/// Stack: [...] -> [..., value]
pub fn opCallvalue(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get gas price (GASPRICE).
///
/// Stack: [...] -> [..., price]
pub fn opGasprice(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get balance of currently executing account (SELFBALANCE) - EIP-1884.
///
/// Stack: [...] -> [..., balance]
pub fn opSelfbalance(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Calldata Operations
// ============================================================================

/// Load word from input data (CALLDATALOAD).
///
/// Stack: [..., offset] -> [..., data]
pub fn opCalldataload(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get size of input data (CALLDATASIZE).
///
/// Stack: [...] -> [..., size]
pub fn opCalldatasize(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Copy input data to memory (CALLDATACOPY).
///
/// Stack: [..., destOffset, offset, length] -> [...]
pub fn opCalldatacopy(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Code Operations
// ============================================================================

/// Get size of code (CODESIZE).
///
/// Stack: [...] -> [..., size]
pub fn opCodesize(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Copy code to memory (CODECOPY).
///
/// Stack: [..., destOffset, offset, length] -> [...]
pub fn opCodecopy(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get size of external code (EXTCODESIZE).
///
/// Stack: [..., address] -> [..., size]
pub fn opExtcodesize(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Copy external code to memory (EXTCODECOPY).
///
/// Stack: [..., address, destOffset, offset, length] -> [...]
pub fn opExtcodecopy(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get hash of external code (EXTCODEHASH) - EIP-1052.
///
/// Stack: [..., address] -> [..., hash]
pub fn opExtcodehash(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Return Data Operations
// ============================================================================

/// Get size of return data (RETURNDATASIZE) - EIP-211.
///
/// Stack: [...] -> [..., size]
pub fn opReturndatasize(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Copy return data to memory (RETURNDATACOPY) - EIP-211.
///
/// Stack: [..., destOffset, offset, length] -> [...]
pub fn opReturndatacopy(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Block Information
// ============================================================================

/// Get hash of recent complete block (BLOCKHASH).
///
/// Stack: [..., blockNumber] -> [..., hash]
pub fn opBlockhash(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get block's beneficiary address (COINBASE).
///
/// Stack: [...] -> [..., address]
pub fn opCoinbase(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get block's timestamp (TIMESTAMP).
///
/// Stack: [...] -> [..., timestamp]
pub fn opTimestamp(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get block's number (NUMBER).
///
/// Stack: [...] -> [..., number]
pub fn opNumber(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get block's difficulty / PREVRANDAO (DIFFICULTY/PREVRANDAO).
///
/// Stack: [...] -> [..., difficulty]
/// Note: Post-merge this returns PREVRANDAO (EIP-4399)
pub fn opPrevrandao(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get block's gas limit (GASLIMIT).
///
/// Stack: [...] -> [..., limit]
pub fn opGaslimit(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get chain ID (CHAINID) - EIP-1344.
///
/// Stack: [...] -> [..., chainId]
pub fn opChainid(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get base fee (BASEFEE) - EIP-3198.
///
/// Stack: [...] -> [..., baseFee]
pub fn opBasefee(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get versioned hash of blob at index (BLOBHASH) - EIP-4844.
///
/// Stack: [..., index] -> [..., versionedHash]
pub fn opBlobhash(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Get blob base fee (BLOBBASEFEE) - EIP-7516.
///
/// Stack: [...] -> [..., blobBaseFee]
pub fn opBlobbasefee(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================
