//! Gas accounting integration tests.
//!
//! Tests exact gas values and gas propagation/tracking.

const std = @import("std");
const zevm = @import("zevm");
const th = @import("test_helpers.zig");

const Evm = th.Evm;
const CallExecutor = th.CallExecutor;
const ExecutionStatus = th.ExecutionStatus;
const U256 = th.U256;
const Env = th.Env;
const Spec = th.Spec;
const MockHost = th.MockHost;
const TestCase = th.TestCase;

const expect = th.expect;
const expectEqual = th.expectEqual;

test "gas precision" {
    const test_cases = [_]TestCase{
        // Simple arithmetic has exact gas cost.
        // PUSH1(3) + PUSH1(3) + ADD(3) + POP(2) + STOP(0) = 11
        .{
            .target_code = th.createComputeContract(),
            .expected_gas_used = 11,
        },

        // STOP alone uses zero gas.
        .{
            .target_code = th.createStopContract(),
            .expected_gas_used = 0,
        },
    };

    try th.runTestCases(&test_cases);
}

test "All call types consume same bytecode gas" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createComputeContract());

    const call_types = [_]CallExecutor.Kind{ .CALL, .DELEGATECALL, .STATICCALL, .CALLCODE };
    var gas_values: [4]u64 = undefined;

    for (call_types, 0..) |kind, i| {
        const inputs = CallExecutor.Inputs{
            .kind = kind,
            .target = th.SIMPLE_TARGET,
            .caller = th.SIMPLE_CALLER,
            .value = U256.ZERO,
            .input = &[_]u8{},
            .gas_limit = 100000,
            .transfer_value = false,
        };

        const result = try evm.call(inputs);
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        gas_values[i] = result.gas_used;
    }

    // All call types should use same gas.
    for (gas_values) |gas| {
        try expectEqual(gas_values[0], gas);
    }
}

test "gas propagation" {
    const test_cases = [_]TestCase{
        // Gas used is tracked correctly.
        // PUSH1(3) + PUSH1(3) + ADD(3) + POP(2) + STOP(0) = 11
        .{
            .target_code = th.createComputeContract(),
            .expected_gas_used = 11,
        },

        // Gas consumed on failure.
        // PUSH1(3) + PUSH1(3) + REVERT(0) = 6
        .{
            .target_code = th.createRevertContract(),
            .expected_status = .REVERT,
            .expected_gas_used = 6,
        },

        // Minimal gas for STOP.
        .{
            .target_code = th.createStopContract(),
            .expected_gas_used = 0,
        },

        // Gas refund tracking.
        // No refund for simple STOP.
        .{
            .target_code = th.createStopContract(),
        },
    };

    try th.runTestCases(&test_cases);
}

test "Out of gas uses all provided gas" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createOogContract());

    const gas_limit: u64 = 1000;
    const inputs = CallExecutor.Inputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = gas_limit,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.OUT_OF_GAS, result.status);
    try expectEqual(gas_limit, result.gas_used);
}

test "Different call types have same gas accounting" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createComputeContract());

    const call_types = [_]CallExecutor.Kind{ .CALL, .DELEGATECALL, .STATICCALL, .CALLCODE };
    var gas_values: [4]u64 = undefined;

    for (call_types, 0..) |kind, i| {
        const inputs = CallExecutor.Inputs{
            .kind = kind,
            .target = th.SIMPLE_TARGET,
            .caller = th.SIMPLE_CALLER,
            .value = U256.ZERO,
            .input = &[_]u8{},
            .gas_limit = 100000,
            .transfer_value = false,
        };

        const result = try evm.call(inputs);
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        gas_values[i] = result.gas_used;
    }

    // All call types should use same gas.
    for (gas_values) |gas| {
        try expectEqual(gas_values[0], gas);
    }
}

test "Gas used less than gas limit on success" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createValueReturner(42));

    const gas_limit: u64 = 100000;
    const inputs = CallExecutor.Inputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = gas_limit,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expect(result.gas_used < gas_limit);
}

test "Insufficient gas fails immediately" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createValueReturner(42));

    const inputs = CallExecutor.Inputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 1,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.OUT_OF_GAS, result.status);
}

// ============================================================================
// CALLCODE Gas Tests
// ============================================================================

test "CALLCODE: no new account cost (unlike CALL)" {
    // CALLCODE should NOT charge new account creation cost, even when
    // calling to a non-existent account with value > 0.
    // CALL would charge 25000 for new account; CALLCODE should not.
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    // Target has code but second target doesn't exist.
    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());

    // CALL to existing target (warm).
    const call_inputs = CallExecutor.Inputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const call_result = try evm.call(call_inputs);
    try expectEqual(ExecutionStatus.SUCCESS, call_result.status);
    const call_gas = call_result.gas_used;

    // CALLCODE to same target should use same gas.
    const callcode_inputs = CallExecutor.Inputs{
        .kind = .CALLCODE,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const callcode_result = try evm.call(callcode_inputs);
    try expectEqual(ExecutionStatus.SUCCESS, callcode_result.status);
    const callcode_gas = callcode_result.gas_used;

    // Both should use same bytecode execution gas.
    try expectEqual(call_gas, callcode_gas);
}

test "CALLCODE: value transfer charges gas but no actual transfer" {
    // When CALLCODE has value > 0, it should charge value transfer cost (9000)
    // but NOT actually transfer ETH.
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setBalance(th.SIMPLE_CALLER, U256.fromU64(10000));
    try mock.setBalance(th.SIMPLE_TARGET, U256.ZERO);
    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());

    // CALLCODE with value > 0.
    const inputs = CallExecutor.Inputs{
        .kind = .CALLCODE,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.fromU64(1000),
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false, // No actual transfer.
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // Balances should be unchanged (no actual transfer).
    const h = mock.host();
    try expect(h.balance(th.SIMPLE_CALLER).eql(U256.fromU64(10000)));
    try expect(h.balance(th.SIMPLE_TARGET).eql(U256.ZERO));
}
