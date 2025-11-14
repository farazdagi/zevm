//! Storage operation instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Load word from storage (SLOAD).
///
/// Stack: [..., key] -> [..., value]
/// Note: This operation needs access to the storage state.
/// It will be handled specially in the interpreter's execute() function.
pub fn opSload(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Store word to storage (SSTORE).
///
/// Stack: [..., key, value] -> [...]
/// Note: This operation needs access to the storage state and has complex gas costs.
/// It will be handled specially in the interpreter's execute() function.
pub fn opSstore(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Load word from transient storage (TLOAD) - EIP-1153.
///
/// Stack: [..., key] -> [..., value]
/// Note: This operation needs access to the transient storage state.
/// It will be handled specially in the interpreter's execute() function.
pub fn opTload(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Store word to transient storage (TSTORE) - EIP-1153.
///
/// Stack: [..., key, value] -> [...]
/// Note: This operation needs access to the transient storage state.
/// It will be handled specially in the interpreter's execute() function.
pub fn opTstore(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================
