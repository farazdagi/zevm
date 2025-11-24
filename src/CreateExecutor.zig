//! Interface for executing contract creation operations.
//!
//! CreateExecutor is a vtable-based interface that allows the Interpreter to
//! create contracts without depending on the Evm type directly. This pattern
//! enables decoupling between the interpreter and the EVM execution layer.

const Address = @import("primitives/mod.zig").Address;
const U256 = @import("primitives/mod.zig").U256;
const B256 = @import("primitives/mod.zig").B256;
const ExecutionStatus = @import("interpreter/interpreter.zig").ExecutionStatus;

const CreateExecutor = @This();

/// Creation kind determines address calculation method.
pub const Kind = union(enum) {
    /// CREATE: address = keccak256(rlp([sender, nonce]))[12:].
    CREATE,

    /// CREATE2
    /// address = keccak256(0xff ++ sender ++ salt ++ keccak256(init_code))[12:].
    CREATE2: U256,
};

/// Input parameters for contract creation.
pub const Inputs = struct {
    /// Address creating the contract (caller).
    caller: Address,

    /// Creation kind (CREATE or CREATE2 with salt).
    kind: Kind,

    /// Value to transfer to new contract (in wei).
    value: U256,

    /// Initialization code to execute.
    init_code: []const u8,

    /// Gas limit for initialization.
    gas_limit: u64,
};

/// Result of contract creation.
pub const Result = struct {
    /// Execution status.
    status: ExecutionStatus,

    /// Gas consumed by creation.
    gas_used: u64,

    /// Gas refunded.
    gas_refund: i64,

    /// Deployed contract address (null if creation failed).
    address: ?Address,

    /// Return data (on revert, contains error message).
    output: []const u8,
};

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    /// Execute contract creation.
    create: *const fn (ptr: *anyopaque, inputs: Inputs) anyerror!Result,
};

/// Execute contract creation.
pub inline fn create(self: CreateExecutor, inputs: Inputs) !Result {
    return self.vtable.create(self.ptr, inputs);
}

/// Create a no-op executor for testing.
/// All creations return failure with no address.
pub fn noOp() CreateExecutor {
    const S = struct {
        fn createNoop(_: *anyopaque, inputs: Inputs) anyerror!Result {
            _ = inputs;
            return .{
                .status = .REVERT,
                .gas_used = 0,
                .gas_refund = 0,
                .address = null,
                .output = &[_]u8{},
            };
        }
    };

    return .{
        .ptr = undefined,
        .vtable = &.{
            .create = S.createNoop,
        },
    };
}

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "CreateExecutor.Kind: CREATE variant" {
    const kind = Kind.CREATE;
    try expectEqual(Kind.CREATE, kind);
}

test "CreateExecutor.Kind: CREATE2 with salt" {
    const salt = U256.fromU64(0x1234);
    const kind = Kind{ .CREATE2 = salt };

    switch (kind) {
        .CREATE => unreachable,
        .CREATE2 => |s| try expect(salt.eql(s)),
    }
}

test "CreateExecutor.Inputs: initialization" {
    const caller = Address.zero();
    const value = U256.fromU64(100);
    const init_code = &[_]u8{ 0x60, 0x00 };
    const gas_limit: u64 = 50000;

    const inputs = Inputs{
        .caller = caller,
        .kind = .CREATE,
        .value = value,
        .init_code = init_code,
        .gas_limit = gas_limit,
    };

    try expect(caller.eql(inputs.caller));
    try expectEqual(Kind.CREATE, inputs.kind);
    try expect(value.eql(inputs.value));
    try expectEqual(gas_limit, inputs.gas_limit);
}

test "CreateExecutor: noOp returns failure" {
    const executor = CreateExecutor.noOp();
    const inputs = Inputs{
        .caller = Address.zero(),
        .kind = .CREATE,
        .value = U256.ZERO,
        .init_code = &[_]u8{},
        .gas_limit = 10000,
    };

    const result = try executor.create(inputs);
    try expectEqual(ExecutionStatus.REVERT, result.status);
    try expectEqual(null, result.address);
    try expectEqual(0, result.gas_used);
}
