//! Interface for executing nested call operations.
//!
//! CallExecutor is a vtable-based interface that allows the Interpreter to make
//! calls without depending on the Evm type directly. This pattern enables
//! decoupling between the interpreter and the EVM execution layer.

const Address = @import("primitives/mod.zig").Address;
const U256 = @import("primitives/mod.zig").U256;
const ExecutionStatus = @import("interpreter/interpreter.zig").ExecutionStatus;

const CallExecutor = @This();

/// Call kind determines the type of call operation.
pub const Kind = enum {
    /// Normal call: transfers value, changes context.
    CALL,

    /// Legacy call: like CALL but deprecated.
    CALLCODE,

    /// Delegate call: preserves caller, no value transfer.
    DELEGATECALL,

    /// Static call: read-only, no state modifications allowed.
    STATICCALL,
};

/// Input parameters for a call operation.
pub const Inputs = struct {
    /// Type of call.
    kind: Kind,

    /// Target contract address to call.
    target: Address,

    /// Address initiating this call.
    caller: Address,

    /// Value to transfer (in wei).
    value: U256,

    /// Input data.
    input: []const u8,

    /// Gas limit for this call.
    gas_limit: u64,

    /// Whether to actually transfer value (false for DELEGATECALL).
    transfer_value: bool,
};

/// Result of a call operation.
pub const Result = struct {
    /// Execution status.
    status: ExecutionStatus,

    /// Gas consumed by the call.
    gas_used: u64,

    /// Gas refunded by the call.
    gas_refund: i64,

    /// Output data from the call.
    output: []const u8,
};

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    /// Execute a nested call.
    call: *const fn (ptr: *anyopaque, inputs: Inputs) anyerror!Result,
};

/// Execute a nested call.
pub inline fn call(self: CallExecutor, inputs: Inputs) !Result {
    return self.vtable.call(self.ptr, inputs);
}

/// Create a no-op executor for testing.
/// All calls return failure with empty return data.
pub fn noOp() CallExecutor {
    const S = struct {
        fn callNoop(_: *anyopaque, inputs: Inputs) anyerror!Result {
            _ = inputs;
            return .{
                .status = .REVERT,
                .gas_used = 0,
                .gas_refund = 0,
                .output = &[_]u8{},
            };
        }
    };

    return .{
        .ptr = undefined,
        .vtable = &.{
            .call = S.callNoop,
        },
    };
}
