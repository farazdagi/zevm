//! Execution context integration tests.
//!
//! Tests context opcodes: CALLER, CALLVALUE, ADDRESS, ORIGIN, CODESIZE.

const std = @import("std");
const zevm = @import("zevm");
const th = @import("test_helpers.zig");

const Evm = th.Evm;
const CallInputs = th.CallInputs;
const ExecutionStatus = th.ExecutionStatus;
const Address = th.Address;
const U256 = th.U256;
const Env = th.Env;
const Spec = th.Spec;
const MockHost = th.MockHost;
const TestCase = th.TestCase;

const expect = th.expect;
const expectEqual = th.expectEqual;

test "call context" {
    const test_cases = [_]TestCase{
        // CALLER returns correct address.
        .{
            .target_code = th.createCallerReturner(),
            .expected_output_len = 32,
            .expected_caller_in_output = th.SIMPLE_CALLER,
        },

        // ADDRESS returns callee address for CALL.
        .{
            .target_code = th.createAddressReturner(),
            .expected_output_len = 32,
            .expected_address_in_output = th.SIMPLE_TARGET,
        },

        // ADDRESS returns caller address for DELEGATECALL.
        .{
            .kind = .DELEGATECALL,
            .target_code = th.createAddressReturner(),
            .expected_output_len = 32,
            .expected_address_in_output = th.SIMPLE_CALLER,
        },

        // Self-call preserves context.
        // When A calls itself, inner sees outer as caller.
        .{
            .target_code = th.createCallerReturner(),
            .expected_output_len = 32,
            .expected_caller_in_output = th.SIMPLE_CALLER,
        },

        // Context unchanged after failed call.
        .{
            .target_code = th.createRevertContract(),
            .expected_status = .REVERT,
            .expected_final_depth = 0,
        },
    };

    try th.runTestCases(&test_cases);
}

test "CALLVALUE returns correct value" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const value: u64 = 12345;

    try mock.setCode(th.SIMPLE_TARGET, th.createCallvalueReturner());
    try mock.setBalance(th.SIMPLE_CALLER, U256.fromU64(100000));

    const inputs = CallInputs{
        .kind = .CALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.fromU64(value),
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = true,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(32, result.output.len);

    const returned_value = th.extractU64FromReturn(result.output);
    try expectEqual(value, returned_value);
}

test "ORIGIN always returns tx.origin" {
    const allocator = std.testing.allocator;
    var env = Env.default();

    // Set tx.origin in the environment.
    env.tx.origin = th.ORIGIN;

    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, th.createOriginReturner());

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
    try expectEqual(32, result.output.len);

    const returned_origin = th.extractAddressFromReturn(result.output);
    try expect(std.mem.eql(u8, &returned_origin.inner.bytes, &th.ORIGIN.inner.bytes));
}

test "CODESIZE returns executing code size" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const code = th.createCodesizeReturner();
    try mock.setCode(th.SIMPLE_TARGET, code);

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
    try expectEqual(32, result.output.len);

    const returned_size = th.extractU64FromReturn(result.output);
    try expectEqual(code.len, returned_size);
}
