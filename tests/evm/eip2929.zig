//! EIP-2929 warm/cold access tracking integration tests.

const std = @import("std");
const helpers = @import("test_helpers.zig");
const zevm = @import("zevm");

const Evm = helpers.Evm;
const Address = helpers.Address;
const U256 = helpers.U256;
const Env = helpers.Env;
const Spec = helpers.Spec;
const MockHost = helpers.MockHost;
const ExecutionStatus = helpers.ExecutionStatus;
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const CallInputs = helpers.CallInputs;
const CallKind = helpers.CallKind;

const CALLER = helpers.CALLER;
const TARGET = helpers.TARGET;
const TARGET2 = helpers.TARGET2;
const ORIGIN = helpers.ORIGIN;

// Precompile address (0x01 = ecRecover).
const PRECOMPILE_1 = Address.init([_]u8{0} ** 19 ++ [_]u8{0x01});

// External address (not pre-warmed).
const EXTERNAL = Address.init([_]u8{0} ** 12 ++ [_]u8{ 0x99, 0x99, 0x99, 0x99, 0x99, 0x99, 0x99, 0x99 });

/// Create bytecode that calls BALANCE on the given address and stops.
/// Stack: [address] -> [balance]
fn createBalanceContract(addr: Address) [25]u8 {
    // PUSH20 address, BALANCE, POP, STOP
    var bytecode: [25]u8 = undefined;
    bytecode[0] = 0x73; // PUSH20
    @memcpy(bytecode[1..21], &addr.inner.bytes);
    bytecode[21] = 0x31; // BALANCE
    bytecode[22] = 0x50; // POP
    bytecode[23] = 0x00; // STOP
    bytecode[24] = 0x00; // Padding
    return bytecode;
}

/// Create bytecode that calls BALANCE twice on the same address (cold then warm).
fn createDoubleBalanceContract(addr: Address) [47]u8 {
    // PUSH20 address, BALANCE, POP, PUSH20 address, BALANCE, POP, STOP
    var bytecode: [47]u8 = undefined;
    // First BALANCE
    bytecode[0] = 0x73; // PUSH20
    @memcpy(bytecode[1..21], &addr.inner.bytes);
    bytecode[21] = 0x31; // BALANCE
    bytecode[22] = 0x50; // POP
    // Second BALANCE
    bytecode[23] = 0x73; // PUSH20
    @memcpy(bytecode[24..44], &addr.inner.bytes);
    bytecode[44] = 0x31; // BALANCE
    bytecode[45] = 0x50; // POP
    bytecode[46] = 0x00; // STOP
    return bytecode;
}

/// Create bytecode that calls SLOAD with the given key and stops.
fn createSloadContract(key: u8) [5]u8 {
    // PUSH1 key, SLOAD, POP, STOP
    return [_]u8{
        0x60, key, // PUSH1 key
        0x54, // SLOAD
        0x50, // POP
        0x00, // STOP
    };
}

/// Create bytecode that calls SLOAD twice with the same key (cold then warm).
fn createDoubleSloadContract(key: u8) [9]u8 {
    // PUSH1 key, SLOAD, POP, PUSH1 key, SLOAD, POP, STOP
    return [_]u8{
        0x60, key, // PUSH1 key
        0x54, // SLOAD
        0x50, // POP
        0x60, key, // PUSH1 key
        0x54, // SLOAD
        0x50, // POP
        0x00, // STOP
    };
}

test "BALANCE account access costs" {
    const TestCase = struct {
        address: Address,
        expected_gas: u64,
        double_balance: bool,
    };

    const test_cases = [_]TestCase{
        // Cold account access charges 2600 gas.
        //
        // Gas breakdown (evm.call() directly, no CALL opcode cost):
        // - PUSH20: 3
        // - BALANCE: 100 (base) + 2500 (cold EXTERNAL) = 2600
        // - POP: 2
        // - STOP: 0
        // Total: 3 + 2600 + 2 + 0 = 2605
        .{
            .address = EXTERNAL,
            .expected_gas = 2605,
            .double_balance = false,
        },

        // Warm account access charges 100 gas (second access to same address).
        //
        // Gas breakdown (evm.call() directly, no CALL opcode cost):
        // - First BALANCE: PUSH20(3) + BALANCE(100+2500) + POP(2) = 2605
        // - Second BALANCE: PUSH20(3) + BALANCE(100+0) + POP(2) = 105 (warm)
        // - STOP: 0
        // Total: 2605 + 105 + 0 = 2710
        .{
            .address = EXTERNAL,
            .expected_gas = 2710,
            .double_balance = true,
        },

        // Precompile addresses are pre-warmed.
        //
        // Gas breakdown (precompile is warm, no CALL opcode cost):
        // - PUSH20: 3
        // - BALANCE: 100 (base) + 0 (precompile already warm) = 100
        // - POP: 2
        // - STOP: 0
        // Total: 3 + 100 + 2 + 0 = 105
        .{
            .address = PRECOMPILE_1,
            .expected_gas = 105,
            .double_balance = false,
        },

        // Sender address is pre-warmed.
        //
        // Gas breakdown (sender is warm, no CALL opcode cost):
        // - PUSH20: 3
        // - BALANCE: 100 (base) + 0 (sender already warm) = 100
        // - POP: 2
        // - STOP: 0
        // Total: 3 + 100 + 2 + 0 = 105
        .{
            .address = CALLER,
            .expected_gas = 105,
            .double_balance = false,
        },

        // Transaction recipient is pre-warmed.
        //
        // Gas breakdown (evm.call() directly, no CALL opcode cost):
        // - PUSH20: 3
        // - BALANCE: 100 (base) + 0 (TARGET is warm, it's tx.to) = 100
        // - POP: 2
        // - STOP: 0
        // Total: 3 + 100 + 2 + 0 = 105
        .{
            .address = TARGET,
            .expected_gas = 105,
            .double_balance = false,
        },
    };

    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    for (test_cases) |tc| {
        var env = Env.default();
        env.tx.caller = CALLER;
        env.tx.to = TARGET;

        var mock = MockHost.init(allocator);
        defer mock.deinit();

        var evm = Evm.init(allocator, &env, mock.host(), spec);
        defer evm.deinit();

        // Create appropriate bytecode.
        if (tc.double_balance) {
            const bytecode = createDoubleBalanceContract(tc.address);
            try mock.setCode(TARGET, &bytecode);
        } else {
            const bytecode = createBalanceContract(tc.address);
            try mock.setCode(TARGET, &bytecode);
        }

        const inputs = CallInputs{
            .kind = .CALL,
            .target = TARGET,
            .caller = CALLER,
            .value = U256.ZERO,
            .input = &[_]u8{},
            .gas_limit = 100000,
            .transfer_value = false,
        };

        const result = try evm.call(inputs);
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        try expectEqual(tc.expected_gas, result.gas_used);
    }
}

// NOTE: SLOAD tests are skipped because the SLOAD handler is not yet implemented.
// Once implemented, add tests for:
// - cold storage slot charges 2100 gas
// - warm storage slot charges 100 gas

test "Pre-Berlin forks use fixed costs" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    env.tx.caller = CALLER;
    env.tx.to = TARGET;

    var mock = MockHost.init(allocator);
    defer mock.deinit();

    // Use Istanbul (pre-Berlin).
    const spec = Spec.forFork(.ISTANBUL);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    // Create contract that calls BALANCE twice.
    const bytecode = createDoubleBalanceContract(EXTERNAL);
    try mock.setCode(TARGET, &bytecode);

    const inputs = CallInputs{
        .kind = .CALL,
        .target = TARGET,
        .caller = CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // In Istanbul, BALANCE has fixed cost of 700 (no cold/warm distinction).
    // Gas breakdown (evm.call() directly, no CALL opcode cost):
    // - First BALANCE: PUSH20(3) + BALANCE(700) + POP(2) = 705
    // - Second BALANCE: PUSH20(3) + BALANCE(700) + POP(2) = 705
    // - STOP: 0
    // Total: 705 + 705 + 0 = 1410
    try expectEqual(@as(u64, 1410), result.gas_used);
}
