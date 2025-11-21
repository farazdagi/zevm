//! Storage operations integration tests.
//!
//! Tests SLOAD, SSTORE, TLOAD, TSTORE through EVM execution.

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

const expect = th.expect;
const expectEqual = th.expectEqual;

// Standard Test Addresses
const CALLER = th.CALLER;
const TARGET = th.TARGET;

/// SLOAD from slot 0 and return value.
/// PUSH1 0, SLOAD, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
fn createSloadContract() []const u8 {
    return &[_]u8{
        0x60, 0x00, // PUSH1 0 (slot)
        0x54, // SLOAD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

/// SSTORE value 42 to slot 0, then STOP.
/// PUSH1 42, PUSH1 0, SSTORE, STOP
fn createSstoreContract() []const u8 {
    return &[_]u8{
        0x60, 0x2A, // PUSH1 42 (value)
        0x60, 0x00, // PUSH1 0 (slot)
        0x55, // SSTORE
        0x00, // STOP
    };
}

/// SSTORE value to slot, then SLOAD it back and return.
fn createSstoreSloadContract(comptime slot: u8, comptime value: u8) []const u8 {
    return &[_]u8{
        0x60, value, // PUSH1 value
        0x60, slot, // PUSH1 slot
        0x55, // SSTORE
        0x60, slot, // PUSH1 slot
        0x54, // SLOAD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

/// TLOAD from slot 0 and return value.
fn createTloadContract() []const u8 {
    return &[_]u8{
        0x60, 0x00, // PUSH1 0 (slot)
        0x5C, // TLOAD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

/// TSTORE then TLOAD and return.
fn createTstoreTloadContract(comptime slot: u8, comptime value: u8) []const u8 {
    return &[_]u8{
        0x60, value, // PUSH1 value
        0x60, slot, // PUSH1 slot
        0x5D, // TSTORE
        0x60, slot, // PUSH1 slot
        0x5C, // TLOAD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

test "storage: basic SLOAD returns zero for uninitialized slot" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    try mock.setCode(TARGET, createSloadContract());
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

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
    try expect(result.output.len >= 32);
    // Uninitialized slot returns zero - check last byte.
    try expectEqual(@as(u8, 0), result.output[31]);
}

test "storage: SSTORE then SLOAD returns stored value" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    try mock.setCode(TARGET, createSstoreSloadContract(0, 42));
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

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
    try expect(result.output.len >= 32);
    // Value 42 in last byte.
    try expectEqual(@as(u8, 42), result.output[31]);
}

test "storage: SLOAD reads pre-existing storage" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    // Pre-set storage value to 99 (fits in one byte).
    try mock.setStorage(TARGET, U256.ZERO, U256.fromU64(99));
    try mock.setCode(TARGET, createSloadContract());
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

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
    try expect(result.output.len >= 32);
    try expectEqual(@as(u8, 99), result.output[31]);
}

test "storage: TLOAD returns zero for uninitialized transient slot" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    try mock.setCode(TARGET, createTloadContract());
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

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
    try expect(result.output.len >= 32);
    try expectEqual(@as(u8, 0), result.output[31]);
}

test "storage: TSTORE then TLOAD returns stored value" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    try mock.setCode(TARGET, createTstoreTloadContract(0, 77));
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

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
    try expect(result.output.len >= 32);
    try expectEqual(@as(u8, 77), result.output[31]);
}

test "storage: SSTORE SET gas (zero to non-zero)" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    try mock.setCode(TARGET, createSstoreContract());
    const spec = Spec.forFork(.ISTANBUL);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

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
    // PUSH1(3) + PUSH1(3) + SSTORE(20000 SET) + STOP(0) = 20006.
    const expected_gas_used: u64 = 20006;
    try expectEqual(expected_gas_used, result.gas_used);
}

test "storage: SSTORE RESET gas (non-zero to non-zero)" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    // Pre-set slot to non-zero value.
    try mock.setStorage(TARGET, U256.ZERO, U256.fromU64(1));
    try mock.setCode(TARGET, createSstoreContract());
    const spec = Spec.forFork(.ISTANBUL);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

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
    // PUSH1(3) + PUSH1(3) + SSTORE(5000 RESET) + STOP(0) = 5006.
    const expected_gas_used: u64 = 5006;
    try expectEqual(expected_gas_used, result.gas_used);
}

test "storage: SSTORE no-op same value" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    // Pre-set slot to same value we'll write (42).
    try mock.setStorage(TARGET, U256.ZERO, U256.fromU64(42));
    try mock.setCode(TARGET, createSstoreContract());
    const spec = Spec.forFork(.ISTANBUL);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

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
    // PUSH1(3) + PUSH1(3) + SSTORE(800 no-op, Istanbul cold_sload_cost) + STOP(0) = 806.
    const expected_gas_used: u64 = 806;
    try expectEqual(expected_gas_used, result.gas_used);
}

/// SSTORE value 100 to slot 0, then STOP.
fn createSstore100Contract() []const u8 {
    return &[_]u8{
        0x60, 0x64, // PUSH1 100 (value)
        0x60, 0x00, // PUSH1 0 (slot)
        0x55, // SSTORE
        0x00, // STOP
    };
}

/// SSTORE value 200 to slot 0, then STOP.
fn createSstore200Contract() []const u8 {
    return &[_]u8{
        0x60, 0xC8, // PUSH1 200 (value)
        0x60, 0x00, // PUSH1 0 (slot)
        0x55, // SSTORE
        0x00, // STOP
    };
}

test "storage: sequential transactions track original values correctly" {
    // REGRESSION TEST: This verifies that when multiple transactions run in sequence,
    // each transaction correctly tracks the "original" storage value.
    //
    // Scenario:
    // - Transaction 1: Write 100 to slot 0 (original=0, current=0, new=100) → SET gas
    // - Transaction 2: Write 200 to slot 0 (original=100, current=100, new=200) → RESET gas
    //
    // BUG: If original_storage isn't cleared between transactions, tx2 will see:
    //   original=0 (wrong!), current=100, new=200 → "subsequent change" gas (800)
    //
    // CORRECT: After clearing, tx2's first SSTORE lazily captures:
    //   original=100, current=100, new=200 → "first change RESET" gas (5000)
    //
    // Gas breakdown for tx2:
    // - PUSH1(3) + PUSH1(3) + SSTORE(?) + STOP(0)
    // - If original=current (first change): SSTORE = 5000 (RESET) → total = 5006
    // - If original!=current (subsequent): SSTORE = 800 (warm read) → total = 806

    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    const spec = Spec.forFork(.ISTANBUL);

    // Set up contracts for both transactions.
    try mock.setCode(TARGET, createSstore100Contract());

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const inputs = CallInputs{
        .kind = .CALL,
        .target = TARGET,
        .caller = CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    // Transaction 1: Write 100 to slot 0.
    // original=0, current=0, new=100 → SET (20000 gas).
    const result1 = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result1.status);
    try expectEqual(@as(u64, 20006), result1.gas_used); // SET gas

    // CRITICAL: Clear transaction state between transactions.
    // With lazy tracking, this clears original_storage so tx2 captures fresh originals.
    mock.clearTransactionState();

    // Switch to tx2 contract.
    try mock.setCode(TARGET, createSstore200Contract());

    // Transaction 2: Write 200 to slot 0.
    // CORRECT: original=100, current=100, new=200 → RESET (5000 gas).
    // BUG: original=0 (stale), current=100, new=200 → subsequent change (800 gas).
    const result2 = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result2.status);

    // This assertion will FAIL with current code (expects 5006, gets 806).
    // After implementing lazy tracking + clearTransactionState(), it will PASS.
    const expected_tx2_gas: u64 = 5006; // RESET gas (first change in tx2)
    try expectEqual(expected_tx2_gas, result2.gas_used);
}

const sstore = zevm.gas.sstore;
const Hardfork = zevm.hardfork.Hardfork;
const Host = zevm.host.Host;

test "storage: SSTORE gas and refund across forks" {
    // Frontier-Byzantium: Simple set/reset model
    // Istanbul (EIP-2200): Net gas metering with original/current/new tracking
    // Berlin (EIP-2929): Added cold/warm access costs
    // London (EIP-3529): Reduced refunds

    const TestCase = struct {
        fork: Hardfork,
        original: u64,
        current: u64,
        new: u64,
        is_cold: bool,
        expected_gas: u64,
        expected_refund: i64,
    };

    const test_cases = [_]TestCase{
        // ===== FRONTIER: Simple set/reset model =====
        // Zero to non-zero: SET
        .{
            .fork = .FRONTIER,
            .original = 0,
            .current = 0,
            .new = 1,
            .is_cold = false,
            .expected_gas = 20000, // SET
            .expected_refund = 0,
        },
        // Non-zero to non-zero: RESET
        .{
            .fork = .FRONTIER,
            .original = 1,
            .current = 1,
            .new = 2,
            .is_cold = false,
            .expected_gas = 5000, // RESET
            .expected_refund = 0,
        },
        // Non-zero to zero: RESET + refund
        .{
            .fork = .FRONTIER,
            .original = 1,
            .current = 1,
            .new = 0,
            .is_cold = false,
            .expected_gas = 5000, // RESET
            .expected_refund = 15000, // Clear refund
        },

        // ===== ISTANBUL: Net gas metering =====
        // Zero to non-zero: SET
        .{
            .fork = .ISTANBUL,
            .original = 0,
            .current = 0,
            .new = 1,
            .is_cold = false,
            .expected_gas = 20000, // SET
            .expected_refund = 0,
        },
        // Non-zero to different: RESET (first change)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 1,
            .new = 2,
            .is_cold = false,
            .expected_gas = 5000, // RESET
            .expected_refund = 0,
        },
        // Non-zero to zero: CLEAR (first change)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 1,
            .new = 0,
            .is_cold = false,
            .expected_gas = 5000, // RESET
            .expected_refund = 15000, // Clear refund
        },
        // Same value: no-op (Istanbul warm read)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 1,
            .new = 1,
            .is_cold = false,
            .expected_gas = 800, // cold_sload_cost (used as warm read pre-Berlin)
            .expected_refund = 0,
        },
        // Restore to original non-zero (subsequent change)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 2,
            .new = 1,
            .is_cold = false,
            .expected_gas = 800, // Subsequent change: warm read
            .expected_refund = 4200, // RESET - warm_read = 5000 - 800
        },
        // Restore to original zero (subsequent change)
        .{
            .fork = .ISTANBUL,
            .original = 0,
            .current = 1,
            .new = 0,
            .is_cold = false,
            .expected_gas = 800, // Subsequent change: warm read
            .expected_refund = 19200, // SET - warm_read = 20000 - 800
        },
        // Clear then restore (removes clear refund)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 0,
            .new = 1,
            .is_cold = false,
            .expected_gas = 800, // Subsequent change: warm read
            .expected_refund = -10800, // Remove clear refund + restore: -15000 + 4200
        },

        // ===== BERLIN: Cold/warm access + reduced reset cost =====
        // Zero to non-zero: SET (cold)
        .{
            .fork = .BERLIN,
            .original = 0,
            .current = 0,
            .new = 1,
            .is_cold = true,
            .expected_gas = 22100, // SET + cold_sload_cost = 20000 + 2100
            .expected_refund = 0,
        },
        // Zero to non-zero: SET (warm)
        .{
            .fork = .BERLIN,
            .original = 0,
            .current = 0,
            .new = 1,
            .is_cold = false,
            .expected_gas = 20000, // SET (no cold cost)
            .expected_refund = 0,
        },
        // Non-zero to different: RESET (first change, cold)
        .{
            .fork = .BERLIN,
            .original = 1,
            .current = 1,
            .new = 2,
            .is_cold = true,
            .expected_gas = 5000, // RESET - cold + cold = 5000 - 2100 + 2100
            .expected_refund = 0,
        },
        // Non-zero to different: RESET (first change, warm)
        .{
            .fork = .BERLIN,
            .original = 1,
            .current = 1,
            .new = 2,
            .is_cold = false,
            .expected_gas = 2900, // RESET - cold_sload_cost = 5000 - 2100
            .expected_refund = 0,
        },
        // Same value: no-op (warm read)
        .{
            .fork = .BERLIN,
            .original = 1,
            .current = 1,
            .new = 1,
            .is_cold = false,
            .expected_gas = 100, // warm_storage_read_cost
            .expected_refund = 0,
        },
        // Restore to original non-zero (subsequent change)
        .{
            .fork = .BERLIN,
            .original = 1,
            .current = 2,
            .new = 1,
            .is_cold = false,
            .expected_gas = 100, // Subsequent change: warm read
            .expected_refund = 2800, // (RESET - cold) - warm = (5000 - 2100) - 100
        },

        // ===== LONDON: Reduced refunds =====
        // Clear storage (reduced refund)
        .{
            .fork = .LONDON,
            .original = 1,
            .current = 1,
            .new = 0,
            .is_cold = false,
            .expected_gas = 2900, // Same as Berlin
            .expected_refund = 4800, // Reduced from 15000 to 4800 (EIP-3529)
        },
        // Restore to original non-zero (reduced restore bonus)
        .{
            .fork = .LONDON,
            .original = 1,
            .current = 2,
            .new = 1,
            .is_cold = false,
            .expected_gas = 100, // Subsequent change: warm read
            .expected_refund = 2800, // Same calculation as Berlin
        },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        const result = Host.SstoreResult{
            .original_value = U256.fromU64(tc.original),
            .current_value = U256.fromU64(tc.current),
        };
        const new_value = U256.fromU64(tc.new);

        const gas = sstore.sstoreCost(spec, result, new_value, tc.is_cold);
        const refund = sstore.sstoreRefund(spec, result, new_value);

        try expectEqual(tc.expected_gas, gas);
        try expectEqual(tc.expected_refund, refund);
    }
}
