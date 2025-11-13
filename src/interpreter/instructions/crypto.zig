//! Crypto instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Compute Keccak-256 hash (KECCAK256).
///
/// Stack: [..., offset, length] -> [..., hash]
/// Reads data from memory and pushes the keccak256 hash onto the interp.ctx.stack.
/// Note: This operation requires access to memory and has dynamic gas costs.
/// It will be handled specially in the interpreter's execute() function.
pub fn opKeccak256(interp: *Interpreter) !void {
    _ = interp;
    _ = interp;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================
