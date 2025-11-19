//! Call mechanism integration tests.
//!
//! Tests call types, basic execution, and multi-call sequences.

const std = @import("std");
const zevm = @import("zevm");
const th = @import("test_helpers.zig");

const Evm = th.Evm;
const CallInputs = th.CallInputs;
const CallKind = th.CallKind;
const ExecutionStatus = th.ExecutionStatus;
const Address = th.Address;
const U256 = th.U256;
const Env = th.Env;
const Spec = th.Spec;
const MockHost = th.MockHost;
const TestCase = th.TestCase;

const expect = th.expect;
const expectEqual = th.expectEqual;

// ============================================================================
// Basic Calls
// ============================================================================

test "basic calls" {
    const test_cases = [_]TestCase{
        // A calls B - simple nested call.
        // B returns 42.
        .{
            .target_code = th.createValueReturner(42),
            .expected_output_len = 32,
            .expected_output_byte = 42,
        },

        // Call to empty account (no code).
        // Empty execution should succeed.
        .{
            .target_code = null,
            .expected_output_len = 0,
        },

        // Empty return data.
        // B does STOP (no return).
        .{
            .target_code = th.createStopContract(),
            .expected_output_len = 0,
        },

        // Maximum depth (1024) enforcement.
        .{
            .initial_depth = 1024,
            .target_code = th.createStopContract(),
            .expected_status = .CALL_DEPTH_EXCEEDED,
        },

        // Depth at 1023 succeeds.
        .{
            .initial_depth = 1023,
            .target_code = th.createStopContract(),
        },

        // Depth tracking increments and decrements.
        // Start at depth 5, after call should return to 5.
        .{
            .initial_depth = 5,
            .target_code = th.createStopContract(),
            .expected_final_depth = 5,
        },

        // Return data buffer updated after call.
        // B returns 99.
        .{
            .target_code = th.createValueReturner(99),
            .expected_return_buffer_len = 32,
            .expected_return_buffer_byte = 99,
        },
    };

    try th.runTestCases(&test_cases);
}

test "Gas is consumed during call" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    // Use bytecode that actually consumes gas: PUSH1 0x42, POP, STOP.
    // PUSH1 costs 3 gas, POP costs 2 gas, STOP costs 0 gas = 5 gas total.
    const bytecode = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x50, // POP
        0x00, // STOP
    };
    try mock.setCode(th.SIMPLE_TARGET, bytecode);

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // Some gas should have been used (PUSH1 = 3, POP = 2).
    try expect(result.gas_used > 0);
    try expect(result.gas_used < 100000);
}

// ============================================================================
// Call Types
// ============================================================================

test "call types basic" {
    const test_cases = [_]TestCase{
        // STATICCALL: read-only enforcement.
        // LOG0 should fail in static mode.
        .{
            .kind = .STATICCALL,
            .target_code = th.createLogContract(),
            .expected_status = .REVERT,
        },

        // STATICCALL: allows read-only operations.
        .{
            .kind = .STATICCALL,
            .target_code = th.createAddressReturner(),
        },

        // Static mode is set during STATICCALL.
        .{
            .kind = .STATICCALL,
            .target_code = th.createStopContract(),
        },

        // STATICCALL has zero value.
        .{
            .kind = .STATICCALL,
            .target_code = th.createCallvalueReturner(),
            .expected_output_len = 32,
            .expected_value_in_output = 0,
        },

        // CALL returns success status.
        .{
            .kind = .CALL,
            .target_code = th.createStopContract(),
        },

        // DELEGATECALL returns success status.
        .{
            .kind = .DELEGATECALL,
            .target_code = th.createStopContract(),
        },

        // STATICCALL returns success status.
        .{
            .kind = .STATICCALL,
            .target_code = th.createStopContract(),
        },

        // CALLCODE returns success status.
        .{
            .kind = .CALLCODE,
            .target_code = th.createStopContract(),
        },
    };

    try th.runTestCases(&test_cases);
}

test "CALL: value transfer, new context" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const value = U256.fromU64(1000);

    try mock.setBalance(th.SIMPLE_CALLER, U256.fromU64(5000));
    try mock.setBalance(th.SIMPLE_TARGET, U256.fromU64(0));
    try mock.setCode(th.SIMPLE_TARGET, th.createAddressReturner());

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = value,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = true,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // Verify value transferred.
    const h = mock.host();
    try expect(h.balance(th.SIMPLE_CALLER).eql(U256.fromU64(4000)));
    try expect(h.balance(th.SIMPLE_TARGET).eql(U256.fromU64(1000)));

    // ADDRESS should be target for CALL.
    const returned_address = th.extractAddressFromReturn(result.output);
    try expect(std.mem.eql(u8, &returned_address.inner.bytes, &th.SIMPLE_TARGET.inner.bytes));
}

test "DELEGATECALL: no value transfer, preserved context" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setBalance(th.SIMPLE_CALLER, U256.fromU64(5000));
    try mock.setBalance(th.SIMPLE_TARGET, U256.fromU64(0));
    try mock.setCode(th.SIMPLE_TARGET, th.createAddressReturner());

    const inputs = CallInputs{
        .kind = .DELEGATECALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.fromU64(1000),
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // Verify no value transferred.
    const h = mock.host();
    try expect(h.balance(th.SIMPLE_CALLER).eql(U256.fromU64(5000)));
    try expect(h.balance(th.SIMPLE_TARGET).eql(U256.fromU64(0)));

    // ADDRESS should be caller for DELEGATECALL.
    const returned_address = th.extractAddressFromReturn(result.output);
    try expect(std.mem.eql(u8, &returned_address.inner.bytes, &th.SIMPLE_CALLER.inner.bytes));
}

test "CALLCODE: uses caller's context address" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createAddressReturner());

    const inputs = CallInputs{
        .kind = .CALLCODE,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // For CALLCODE, ADDRESS should return target (code address).
    const returned_address = th.extractAddressFromReturn(result.output);
    try expect(std.mem.eql(u8, &returned_address.inner.bytes, &th.SIMPLE_TARGET.inner.bytes));
}

test "DELEGATECALL preserves msg.value" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const value: u64 = 12345;
    try mock.setCode(th.SIMPLE_TARGET, th.createCallvalueReturner());

    const inputs = CallInputs{
        .kind = .DELEGATECALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.fromU64(value),
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    const returned_value = th.extractU64FromReturn(result.output);
    try expectEqual(value, returned_value);
}

// ============================================================================
// Nested/Sequential Calls
// ============================================================================

test "Sequential calls to same target" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createValueReturner(42));

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    // Make multiple calls.
    for (0..5) |_| {
        const result = try evm.call(inputs);
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        try expectEqual(42, result.output[31]);
    }
}

test "Sequential calls to different targets" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const target1 = Address.init([_]u8{0} ** 19 ++ [_]u8{0x10});
    const target2 = Address.init([_]u8{0} ** 19 ++ [_]u8{0x20});
    const target3 = Address.init([_]u8{0} ** 19 ++ [_]u8{0x30});

    try mock.setCode(target1, th.createValueReturner(10));
    try mock.setCode(target2, th.createValueReturner(20));
    try mock.setCode(target3, th.createValueReturner(30));

    const targets = [_]Address{ target1, target2, target3 };
    const expected = [_]u8{ 10, 20, 30 };

    for (targets, expected) |target, exp| {
        const inputs = CallInputs{
            .kind = .CALL,
            .target = target,
            .caller = th.SIMPLE_CALLER,
            .value = U256.ZERO,
            .input = &[_]u8{},
            .gas_limit = 100000,
            .transfer_value = false,
        };

        const result = try evm.call(inputs);
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        try expectEqual(exp, result.output[31]);
    }
}

test "Mixed call types in sequence" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());

    const call_types = [_]CallKind{ .CALL, .DELEGATECALL, .STATICCALL, .CALLCODE };

    for (call_types) |kind| {
        const inputs = CallInputs{
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
    }
}

test "Depth tracking across multiple calls" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    // Verify depth returns to 0 after each call.
    for (0..3) |_| {
        try expectEqual(0, evm.depth);
        const result = try evm.call(inputs);
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        try expectEqual(0, evm.depth);
    }
}

test "Calls at different initial depths" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    // Test at various depths.
    const depths = [_]u16{ 0, 100, 500, 1000, 1023 };

    for (depths) |depth| {
        evm.depth = depth;
        const result = try evm.call(inputs);
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        try expectEqual(depth, evm.depth); // Restored after call.
    }
}

test "Value transfers in sequence" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const target1 = Address.init([_]u8{0} ** 19 ++ [_]u8{0x10});
    const target2 = Address.init([_]u8{0} ** 19 ++ [_]u8{0x20});

    try mock.setBalance(th.SIMPLE_CALLER, U256.fromU64(1000));
    try mock.setBalance(target1, U256.fromU64(0));
    try mock.setBalance(target2, U256.fromU64(0));

    try mock.setCode(target1, th.createStopContract());
    try mock.setCode(target2, th.createStopContract());

    // First transfer: 300 to target1.
    const inputs1 = CallInputs{
        .kind = .CALL,
        .target = target1,
        .caller = th.SIMPLE_CALLER,
        .value = U256.fromU64(300),
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = true,
    };

    const result1 = try evm.call(inputs1);
    try expectEqual(ExecutionStatus.SUCCESS, result1.status);

    // Second transfer: 200 to target2.
    const inputs2 = CallInputs{
        .kind = .CALL,
        .target = target2,
        .caller = th.SIMPLE_CALLER,
        .value = U256.fromU64(200),
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = true,
    };

    const result2 = try evm.call(inputs2);
    try expectEqual(ExecutionStatus.SUCCESS, result2.status);

    // Verify final balances.
    const h = mock.host();
    try expect(h.balance(th.SIMPLE_CALLER).eql(U256.fromU64(500))); // 1000 - 300 - 200
    try expect(h.balance(target1).eql(U256.fromU64(300)));
    try expect(h.balance(target2).eql(U256.fromU64(200)));
}

test "Mixed success and failure in sequence" {
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

    // Success.
    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());
    const r1 = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, r1.status);

    // Failure.
    try mock.setCode(th.SIMPLE_TARGET, th.createRevertContract());
    const r2 = try evm.call(inputs);
    try expectEqual(ExecutionStatus.REVERT, r2.status);

    // Success again.
    try mock.setCode(th.SIMPLE_TARGET, th.createValueReturner(99));
    const r3 = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, r3.status);
    try expectEqual(99, r3.output[31]);
}

test "Static mode not persisted between calls" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());

    // STATICCALL.
    const static_inputs = CallInputs{
        .kind = .STATICCALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const r1 = try evm.call(static_inputs);
    try expectEqual(ExecutionStatus.SUCCESS, r1.status);
    try expect(!evm.is_static); // Restored after call.

    // Normal CALL.
    const call_inputs = CallInputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const r2 = try evm.call(call_inputs);
    try expectEqual(ExecutionStatus.SUCCESS, r2.status);
    try expect(!evm.is_static);
}

test "Calls with varying gas limits" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());

    const gas_limits = [_]u64{ 1000, 10000, 100000, 1000000 };

    for (gas_limits) |gas_limit| {
        const inputs = CallInputs{
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
        try expect(result.gas_used <= gas_limit);
    }
}

test "Return data buffer updates between calls" {
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

    // First call: returns 11.
    try mock.setCode(th.SIMPLE_TARGET, th.createValueReturner(11));
    _ = try evm.call(inputs);
    try expectEqual(11, evm.return_data_buffer[31]);

    // Second call: returns 22.
    try mock.setCode(th.SIMPLE_TARGET, th.createValueReturner(22));
    _ = try evm.call(inputs);
    try expectEqual(22, evm.return_data_buffer[31]);

    // Third call: stops (no return).
    try mock.setCode(th.SIMPLE_TARGET, th.createStopContract());
    _ = try evm.call(inputs);
    try expectEqual(0, evm.return_data_buffer.len);
}
