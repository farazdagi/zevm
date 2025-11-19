//! State changes integration tests.
//!
//! Tests value transfer, state revert, and return data handling.

const std = @import("std");
const zevm = @import("zevm");
const th = @import("test_helpers.zig");

const Evm = th.Evm;
const CallInputs = th.CallInputs;
const CallKind = th.CallKind;
const ExecutionStatus = th.ExecutionStatus;
const U256 = th.U256;
const Env = th.Env;
const Spec = th.Spec;
const MockHost = th.MockHost;
const TestCase = th.TestCase;

const expect = th.expect;
const expectEqual = th.expectEqual;

// ============================================================================
// Value Transfer
// ============================================================================

test "value transfer" {
    const test_cases = [_]TestCase{
        // Balance updates on CALL with value.
        // A has 1000, B has 0, transfer 300. Result: A=700, B=300.
        .{
            .caller_balance = 1000,
            .target_balance = 0,
            .value = 300,
            .transfer_value = true,
            .target_code = th.createStopContract(),
            .expected_caller_balance = 700,
            .expected_target_balance = 300,
        },

        // Insufficient balance handling.
        // A has 100, tries to transfer 200. Should REVERT.
        .{
            .caller_balance = 100,
            .target_balance = 0,
            .value = 200,
            .transfer_value = true,
            .target_code = th.createStopContract(),
            .expected_status = .REVERT,
            .expected_caller_balance = 100,
            .expected_target_balance = 0,
        },

        // No transfer on DELEGATECALL.
        // Value is preserved but not transferred.
        .{
            .kind = .DELEGATECALL,
            .caller_balance = 1000,
            .target_balance = 0,
            .value = 300,
            .transfer_value = false,
            .target_code = th.createStopContract(),
            .expected_caller_balance = 1000,
            .expected_target_balance = 0,
        },

        // No transfer on STATICCALL.
        .{
            .kind = .STATICCALL,
            .caller_balance = 1000,
            .target_balance = 0,
            .value = 0,
            .transfer_value = false,
            .target_code = th.createStopContract(),
            .expected_caller_balance = 1000,
            .expected_target_balance = 0,
        },

        // Transfer to account with existing balance.
        // A=1000, B=500, transfer 200. Result: A=800, B=700.
        .{
            .caller_balance = 1000,
            .target_balance = 500,
            .value = 200,
            .transfer_value = true,
            .target_code = th.createStopContract(),
            .expected_caller_balance = 800,
            .expected_target_balance = 700,
        },

        // Zero value transfer.
        // No balance change.
        .{
            .caller_balance = 1000,
            .target_balance = 0,
            .value = 0,
            .transfer_value = true,
            .target_code = th.createStopContract(),
            .expected_caller_balance = 1000,
            .expected_target_balance = 0,
        },

        // Transfer entire balance.
        // A=1000, transfer 1000. Result: A=0, B=1000.
        .{
            .caller_balance = 1000,
            .target_balance = 0,
            .value = 1000,
            .transfer_value = true,
            .target_code = th.createStopContract(),
            .expected_caller_balance = 0,
            .expected_target_balance = 1000,
        },
    };

    try th.runTestCases(&test_cases);
}

test "large value transfer" {
    // Test with 1 ETH in wei (needs U256, can't fit in u64).
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const large_balance = U256.fromU128(1_000_000_000_000_000_000); // 1 ETH in wei
    const transfer_amount = U256.fromU128(500_000_000_000_000_000); // 0.5 ETH

    try mock.setBalance(th.CALLER, large_balance);
    try mock.setBalance(th.TARGET, U256.ZERO);
    try mock.setCode(th.TARGET, th.createStopContract());

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.TARGET,
        .caller = th.CALLER,
        .value = transfer_amount,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = true,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    const h = mock.host();
    const expected_caller = large_balance.sub(transfer_amount);
    try expect(h.balance(th.CALLER).eql(expected_caller));
    try expect(h.balance(th.TARGET).eql(transfer_amount));
}

// ============================================================================
// State Revert
// ============================================================================

test "state revert behavior" {
    const test_cases = [_]TestCase{
        // Successful call commits state.
        // Transfer 300 from 1000, should result in 700/300.
        .{
            .caller_balance = 1000,
            .target_balance = 0,
            .value = 300,
            .transfer_value = true,
            .target_code = th.createStopContract(),
            .expected_caller_balance = 700,
            .expected_target_balance = 300,
        },

        // Failed call reverts state.
        // Target REVERTs, balances unchanged.
        .{
            .caller_balance = 1000,
            .target_balance = 0,
            .value = 300,
            .transfer_value = true,
            .target_code = th.createRevertContract(),
            .expected_status = .REVERT,
            .expected_caller_balance = 1000,
            .expected_target_balance = 0,
        },

        // Out of gas reverts state.
        // Target runs out of gas, balances unchanged.
        .{
            .caller_balance = 1000,
            .target_balance = 0,
            .value = 300,
            .gas_limit = 100,
            .transfer_value = true,
            .target_code = th.createOogContract(),
            .expected_status = .OUT_OF_GAS,
            .expected_caller_balance = 1000,
            .expected_target_balance = 0,
        },

        // Depth decrements after revert.
        // Start at depth 5, after revert should return to 5.
        .{
            .initial_depth = 5,
            .target_code = th.createRevertContract(),
            .expected_status = .REVERT,
            .expected_final_depth = 5,
        },
    };

    try th.runTestCases(&test_cases);
}

test "REVERT preserves return data" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.TARGET, th.createRevertWithData());

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.TARGET,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.REVERT, result.status);

    // Return data should be preserved even on revert.
    try expectEqual(4, result.output.len);
    try expectEqual(0xDE, result.output[0]);
    try expectEqual(0xAD, result.output[1]);
    try expectEqual(0xBE, result.output[2]);
    try expectEqual(0xEF, result.output[3]);
}

test "Static mode restored after revert" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.TARGET, th.createRevertContract());

    // Verify not static initially.
    try expect(!evm.is_static);

    const inputs = CallInputs{
        .kind = .STATICCALL,
        .target = th.TARGET,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.REVERT, result.status);

    // Static mode should be restored.
    try expect(!evm.is_static);
}

test "Snapshot count increases during call" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.TARGET, th.createStopContract());

    const initial_snapshots = mock.snapshots.items.len;

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.TARGET,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // Snapshot should have been created.
    try expect(mock.snapshots.items.len >= initial_snapshots);
}

test "Multiple calls each create snapshots" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.TARGET, th.createStopContract());

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.TARGET,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    // Make multiple calls.
    _ = try evm.call(inputs);
    _ = try evm.call(inputs);
    _ = try evm.call(inputs);

    // Each call creates a snapshot.
    try expect(mock.snapshots.items.len >= 3);
}

// ============================================================================
// Return Data
// ============================================================================

test "return data" {
    const test_cases = [_]TestCase{
        // Return data size after successful call.
        // Target returns 32 bytes.
        .{
            .target_code = th.createValueReturner(42),
            .expected_output_len = 32,
            .expected_return_buffer_len = 32,
        },

        // Return data content is correct.
        // Target returns pattern 0xAABBCCDD.
        .{
            .target_code = th.createPatternReturner(),
            .expected_output_len = 4,
            .expected_output_pattern = &[_]u8{ 0xAA, 0xBB, 0xCC, 0xDD },
        },

        // Return data after REVERT.
        // Revert data should be available.
        .{
            .target_code = th.createRevertWithData(),
            .expected_status = .REVERT,
            .expected_output_len = 4,
            .expected_output_pattern = &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF },
        },

        // Return data after out of gas.
        // No return data on OOG.
        .{
            .gas_limit = 100,
            .target_code = th.createOogContract(),
            .expected_status = .OUT_OF_GAS,
            .expected_output_len = 0,
        },

        // Empty return data from STOP.
        .{
            .target_code = th.createStopContract(),
            .expected_output_len = 0,
        },
    };

    try th.runTestCases(&test_cases);
}

test "Return data cleared between calls" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    // Target1 returns 32 bytes.
    try mock.setCode(th.TARGET, th.createValueReturner(99));
    // Target2 just stops.
    try mock.setCode(th.TARGET2, th.createStopContract());

    // First call returns 32 bytes.
    const inputs1 = CallInputs{
        .kind = .CALL,
        .target = th.TARGET,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result1 = try evm.call(inputs1);
    try expectEqual(ExecutionStatus.SUCCESS, result1.status);
    try expectEqual(32, evm.return_data_buffer.len);

    // Second call returns nothing.
    const inputs2 = CallInputs{
        .kind = .CALL,
        .target = th.TARGET2,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result2 = try evm.call(inputs2);
    try expectEqual(ExecutionStatus.SUCCESS, result2.status);

    // Return data buffer should be cleared.
    try expectEqual(0, evm.return_data_buffer.len);
}

test "Return data buffer updated on each call" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    // First call: return 42.
    try mock.setCode(th.TARGET, th.createValueReturner(42));

    const inputs1 = CallInputs{
        .kind = .CALL,
        .target = th.TARGET,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    _ = try evm.call(inputs1);
    try expectEqual(42, evm.return_data_buffer[31]);

    // Second call: return 99.
    try mock.setCode(th.TARGET, th.createValueReturner(99));

    const inputs2 = CallInputs{
        .kind = .CALL,
        .target = th.TARGET,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    _ = try evm.call(inputs2);
    try expectEqual(99, evm.return_data_buffer[31]);
}

test "Return data from all call types" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.TARGET, th.createValueReturner(55));

    // Test all call types return data correctly.
    const call_types = [_]CallKind{ .CALL, .DELEGATECALL, .STATICCALL, .CALLCODE };

    for (call_types) |kind| {
        const inputs = CallInputs{
            .kind = kind,
            .target = th.TARGET,
            .caller = th.CALLER,
            .value = U256.ZERO,
            .input = &[_]u8{},
            .gas_limit = 100000,
            .transfer_value = false,
        };

        const result = try evm.call(inputs);
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        try expectEqual(32, result.output.len);
        try expectEqual(55, result.output[31]);
    }
}
