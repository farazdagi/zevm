//! System operation instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Create a new contract (CREATE).
///
/// Stack: [..., value, offset, length] -> [..., address]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub fn opCreate(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Create a new contract with deterministic address (CREATE2) - EIP-1014.
///
/// Stack: [..., value, offset, length, salt] -> [..., address]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub fn opCreate2(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Call another contract (CALL).
///
/// Stack: [..., gas, address, value, argsOffset, argsLength, retOffset, retLength] -> [..., success]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub fn opCall(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Call another contract's code in current context (CALLCODE).
///
/// Stack: [..., gas, address, value, argsOffset, argsLength, retOffset, retLength] -> [..., success]
/// Note: Deprecated in favor of DELEGATECALL.
/// This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub fn opCallcode(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Call another contract's code in current context (DELEGATECALL) - EIP-7.
///
/// Stack: [..., gas, address, argsOffset, argsLength, retOffset, retLength] -> [..., success]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub fn opDelegatecall(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Static call to another contract (STATICCALL) - EIP-214.
///
/// Stack: [..., gas, address, argsOffset, argsLength, retOffset, retLength] -> [..., success]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub fn opStaticcall(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Destroy contract and send funds (SELFDESTRUCT).
///
/// Stack: [..., address] -> []
/// Note: This operation requires state modifications and special handling.
/// It will be handled specially in the interpreter's execute() function.
pub fn opSelfdestruct(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================
