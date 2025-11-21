//! Call types shared between Evm executor and Interpreter.
//!
//! These types define the interface for nested call operations, allowing
//! the Interpreter to make calls without depending on the Evm type directly.

const Address = @import("primitives/mod.zig").Address;
const U256 = @import("primitives/mod.zig").U256;
const ExecutionStatus = @import("interpreter/interpreter.zig").ExecutionStatus;

/// Call kind determines the type of call operation.
pub const CallKind = enum {
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
pub const CallInputs = struct {
    /// Type of call.
    kind: CallKind,

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
pub const CallResult = struct {
    /// Execution status.
    status: ExecutionStatus,

    /// Gas consumed by the call.
    gas_used: u64,

    /// Gas refunded by the call.
    gas_refund: u64,

    /// Output data from the call.
    output: []const u8,
};

/// Interface for executing nested calls.
pub const CallExecutor = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Execute a nested call.
        call: *const fn (ptr: *anyopaque, inputs: CallInputs) anyerror!CallResult,
    };

    /// Execute a nested call.
    pub inline fn call(self: CallExecutor, inputs: CallInputs) !CallResult {
        return self.vtable.call(self.ptr, inputs);
    }

    /// Create a no-op executor for testing.
    /// All calls return failure with empty return data.
    pub fn noOp() CallExecutor {
        const S = struct {
            fn callNoop(_: *anyopaque, inputs: CallInputs) anyerror!CallResult {
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
};
