//! Logging instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Emit log with 0 topics (LOG0).
///
/// Stack: [..., offset, length] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub fn opLog0(interp: *Interpreter) !void {
    // LOG operations are not allowed in static call context (STATICCALL)
    if (interp.evm.?.is_static) {
        return error.StateWriteInStaticCall;
    }
    return error.UnimplementedOpcode;
}

/// Emit log with 1 topic (LOG1).
///
/// Stack: [..., offset, length, topic1] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub fn opLog1(interp: *Interpreter) !void {
    // LOG operations are not allowed in static call context (STATICCALL)
    if (interp.evm.?.is_static) {
        return error.StateWriteInStaticCall;
    }
    return error.UnimplementedOpcode;
}

/// Emit log with 2 topics (LOG2).
///
/// Stack: [..., offset, length, topic1, topic2] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub fn opLog2(interp: *Interpreter) !void {
    // LOG operations are not allowed in static call context (STATICCALL)
    if (interp.evm.?.is_static) {
        return error.StateWriteInStaticCall;
    }
    return error.UnimplementedOpcode;
}

/// Emit log with 3 topics (LOG3).
///
/// Stack: [..., offset, length, topic1, topic2, topic3] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub fn opLog3(interp: *Interpreter) !void {
    // LOG operations are not allowed in static call context (STATICCALL)
    if (interp.evm.?.is_static) {
        return error.StateWriteInStaticCall;
    }
    return error.UnimplementedOpcode;
}

/// Emit log with 4 topics (LOG4).
///
/// Stack: [..., offset, length, topic1, topic2, topic3, topic4] -> [...]
/// Note: This operation requires access to memory and log state.
/// It will be handled specially in the interpreter's execute() function.
pub fn opLog4(interp: *Interpreter) !void {
    // LOG operations are not allowed in static call context (STATICCALL)
    if (interp.evm.?.is_static) {
        return error.StateWriteInStaticCall;
    }
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================
