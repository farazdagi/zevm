//! Error conditions integration tests.
//!
//! Tests various failure scenarios: OOG, invalid opcode, stack underflow, etc.

const std = @import("std");
const th = @import("test_helpers.zig");

const Evm = th.Evm;
const CallInputs = th.CallInputs;
const ExecutionStatus = th.ExecutionStatus;
const U256 = th.U256;
const Env = th.Env;
const Spec = th.Spec;
const MockHost = th.MockHost;
const TestCase = th.TestCase;

const expect = th.expect;
const expectEqual = th.expectEqual;

test "error handling" {
    const test_cases = [_]TestCase{
        // Call to empty account (no code).
        .{
            .target_code = null,
            .expected_output_len = 0,
        },

        // Call depth exceeded.
        .{
            .initial_depth = 1024,
            .target_code = th.createStopContract(),
            .expected_status = .CALL_DEPTH_EXCEEDED,
        },

        // Out of gas.
        .{
            .gas_limit = 100,
            .target_code = th.createOogContract(),
            .expected_status = .OUT_OF_GAS,
        },

        // Invalid opcode.
        .{
            .target_code = th.createInvalidOpcodeContract(),
            .expected_status = .INVALID_OPCODE,
        },

        // Stack underflow.
        .{
            .target_code = th.createStackUnderflowContract(),
            .expected_status = .STACK_UNDERFLOW,
        },

        // Invalid jump destination.
        .{
            .target_code = th.createInvalidJumpContract(),
            .expected_status = .INVALID_JUMP,
        },

        // REVERT returns failure status.
        .{
            .target_code = th.createRevertContract(),
            .expected_status = .REVERT,
        },

        // Error state is reverted.
        // Transfer with invalid opcode, balances should be unchanged.
        .{
            .caller_balance = 1000,
            .target_balance = 0,
            .value = 500,
            .transfer_value = true,
            .target_code = th.createInvalidOpcodeContract(),
            .expected_status = .INVALID_OPCODE,
            .expected_caller_balance = 1000,
            .expected_target_balance = 0,
        },

        // EVM state consistent after errors.
        .{
            .gas_limit = 100,
            .target_code = th.createOogContract(),
            .expected_status = .OUT_OF_GAS,
            .expected_final_depth = 0,
        },
    };

    try th.runTestCases(&test_cases);
}

test "Multiple errors in sequence" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    // First call: revert.
    try mock.setCode(th.SIMPLE_TARGET, th.createRevertContract());
    const result1 = try evm.call(inputs);
    try expectEqual(ExecutionStatus.REVERT, result1.status);

    // Second call: success.
    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());
    const result2 = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result2.status);

    // Third call: invalid opcode.
    try mock.setCode(th.SIMPLE_TARGET, th.createInvalidOpcodeContract());
    const result3 = try evm.call(inputs);
    try expectEqual(ExecutionStatus.INVALID_OPCODE, result3.status);
}
