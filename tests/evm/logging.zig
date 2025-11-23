//! Logging operations (LOG0-LOG4) integration tests.
//!
//! Tests event emission, gas accounting, and snapshot/revert behavior.

const std = @import("std");
const zevm = @import("zevm");
const th = @import("test_helpers.zig");

const Evm = th.Evm;
const CallInputs = th.CallInputs;
const ExecutionStatus = th.ExecutionStatus;
const U256 = th.U256;
const Env = th.Env;
const Spec = th.Spec;
const MockHost = th.MockHost;
const B256 = zevm.primitives.B256;

const expect = th.expect;
const expectEqual = th.expectEqual;

/// Helper: PUSH32 with repeated byte pattern (e.g., 0x11 repeated 32 times).
fn push32Repeated(comptime byte: u8) [33]u8 {
    var result: [33]u8 = undefined;
    result[0] = 0x7F; // PUSH32 opcode
    @memset(result[1..], byte);
    return result;
}

/// Helper: PUSH32 with arbitrary 32-byte data.
fn push32Data(comptime data: [32]u8) [33]u8 {
    var result: [33]u8 = undefined;
    result[0] = 0x7F; // PUSH32 opcode
    result[1..].* = data;
    return result;
}

/// Helper: PUSH1.
fn push1(comptime value: u8) [2]u8 {
    return [_]u8{ 0x60, value };
}

/// LOG0: empty data (offset=0, size=0).
/// Bytecode: PUSH1 0, PUSH1 0, LOG0, STOP
fn createLog0EmptyData() []const u8 {
    const static = struct {
        const bytecode = push1(0) ++ // size
            push1(0) ++ // offset
            [_]u8{ 0xA0, 0x00 }; // LOG0, STOP
    };
    return &static.bytecode;
}

/// LOG1: single topic, empty data.
/// Bytecode: PUSH32 topic1, PUSH1 0, PUSH1 0, LOG1, STOP
fn createLog1SingleTopic() []const u8 {
    const static = struct {
        const bytecode = push32Repeated(0x11) ++ // topic1
            push1(0) ++ // size
            push1(0) ++ // offset
            [_]u8{ 0xA1, 0x00 }; // LOG1, STOP
    };
    return &static.bytecode;
}

/// LOG2: two topics, empty data.
/// Stack for LOG2: [offset, size, topic1, topic2]
/// So push in reverse: topic2, topic1, size, offset
fn createLog2TwoTopics() []const u8 {
    const static = struct {
        const bytecode = push32Repeated(0x22) ++ // topic2
            push32Repeated(0x11) ++ // topic1
            push1(0) ++ // size
            push1(0) ++ // offset
            [_]u8{ 0xA2, 0x00 }; // LOG2, STOP
    };
    return &static.bytecode;
}

/// LOG3: three topics, empty data.
/// Stack for LOG3: [offset, size, topic1, topic2, topic3]
/// So push in reverse: topic3, topic2, topic1, size, offset
fn createLog3ThreeTopics() []const u8 {
    const static = struct {
        const bytecode = push32Repeated(0x33) ++ // topic3
            push32Repeated(0x22) ++ // topic2
            push32Repeated(0x11) ++ // topic1
            push1(0) ++ // size
            push1(0) ++ // offset
            [_]u8{ 0xA3, 0x00 }; // LOG3, STOP
    };
    return &static.bytecode;
}

/// LOG4: four topics (maximum), empty data.
/// Stack for LOG4: [offset, size, topic1, topic2, topic3, topic4]
/// So push in reverse: topic4, topic3, topic2, topic1, size, offset
fn createLog4FourTopics() []const u8 {
    const static = struct {
        const bytecode = push32Repeated(0x44) ++ // topic4
            push32Repeated(0x33) ++ // topic3
            push32Repeated(0x22) ++ // topic2
            push32Repeated(0x11) ++ // topic1
            push1(0) ++ // size
            push1(0) ++ // offset
            [_]u8{ 0xA4, 0x00 }; // LOG4, STOP
    };
    return &static.bytecode;
}

/// LOG0 with 32 bytes of data.
/// Bytecode: PUSH32 data, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, LOG0, STOP
fn createLog0WithData() []const u8 {
    const static = struct {
        const data = [_]u8{
            0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22,
            0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0x00,
            0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22,
            0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0x00,
        };
        const bytecode = push32Data(data) ++
            push1(0) ++ // memory offset
            [_]u8{0x52} ++ // MSTORE
            push1(32) ++ // size
            push1(0) ++ // offset
            [_]u8{ 0xA0, 0x00 }; // LOG0, STOP
    };
    return &static.bytecode;
}

/// Multiple LOG operations in single transaction.
/// Bytecode: LOG0, LOG0, STOP (two empty logs)
fn createMultipleLogs() []const u8 {
    const static = struct {
        const bytecode = push1(0) ++ push1(0) ++ [_]u8{0xA0} ++ // First LOG0
            push1(0) ++ push1(0) ++ [_]u8{0xA0} ++ // Second LOG0
            [_]u8{0x00}; // STOP
    };
    return &static.bytecode;
}

// ============================================================================
// Tests
// ============================================================================

test "LOGn: basic event emission (LOG0-LOG4)" {
    const TestCase = struct {
        bytecode: []const u8,
        expected_topics: []const u8, // First byte of each topic
    };

    const cases = [_]TestCase{
        // LOG0: no topics
        .{
            .bytecode = createLog0EmptyData(),
            .expected_topics = &[_]u8{},
        },
        // LOG1: single topic (0x11...)
        .{
            .bytecode = createLog1SingleTopic(),
            .expected_topics = &[_]u8{0x11},
        },
        // LOG2: two topics (0x11..., 0x22...)
        .{
            .bytecode = createLog2TwoTopics(),
            .expected_topics = &[_]u8{ 0x11, 0x22 },
        },
        // LOG3: three topics (0x11..., 0x22..., 0x33...)
        .{
            .bytecode = createLog3ThreeTopics(),
            .expected_topics = &[_]u8{ 0x11, 0x22, 0x33 },
        },
        // LOG4: four topics (maximum)
        .{
            .bytecode = createLog4FourTopics(),
            .expected_topics = &[_]u8{ 0x11, 0x22, 0x33, 0x44 },
        },
    };

    for (cases) |case| {
        const allocator = std.testing.allocator;
        var env = Env.default();
        var mock = MockHost.init(allocator);
        defer mock.deinit();

        const spec = Spec.forFork(.FRONTIER);
        var evm = Evm.init(allocator, &env, mock.host(), spec);
        defer evm.deinit();

        try mock.setCode(th.SIMPLE_TARGET, case.bytecode);

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

        const logs = mock.getLogs();
        try expectEqual(@as(usize, 1), logs.len);
        try expect(logs[0].address.eql(th.SIMPLE_TARGET));
        try expectEqual(@as(u3, @intCast(case.expected_topics.len)), logs[0].topic_count);

        // Verify topic values (first and last byte of each topic).
        if (case.expected_topics.len > 0) {
            const topics = logs[0].topics();
            for (case.expected_topics, 0..) |expected_byte, i| {
                try expectEqual(expected_byte, topics[i].bytes[0]);
                try expectEqual(expected_byte, topics[i].bytes[31]);
            }
        }
    }
}

test "LOG0: with 32 bytes of data" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    const spec = Spec.forFork(.FRONTIER);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, createLog0WithData());

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

    // Verify log.
    const logs = mock.getLogs();
    try expectEqual(@as(usize, 1), logs.len);
    try expectEqual(@as(u3, 0), logs[0].topic_count);
    try expectEqual(@as(usize, 32), logs[0].data.len);

    // Verify data content.
    try expectEqual(@as(u8, 0xAA), logs[0].data[0]);
    try expectEqual(@as(u8, 0xBB), logs[0].data[1]);
    try expectEqual(@as(u8, 0x00), logs[0].data[31]);
}

test "Multiple logs in single transaction" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    const spec = Spec.forFork(.FRONTIER);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, createMultipleLogs());

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

    // Verify multiple logs.
    const logs = mock.getLogs();
    try expectEqual(@as(usize, 2), logs.len);
    try expect(logs[0].address.eql(th.SIMPLE_TARGET));
    try expect(logs[1].address.eql(th.SIMPLE_TARGET));
}

test "STATICCALL: cannot emit logs (EIP-214)" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    const spec = Spec.forFork(.BYZANTIUM); // EIP-214 introduced in Byzantium
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setCode(th.SIMPLE_TARGET, createLog0EmptyData());

    const inputs = CallInputs{
        .kind = .STATICCALL,
        .target = th.SIMPLE_TARGET,
        .caller = th.SIMPLE_CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.REVERT, result.status);

    // Verify no logs were emitted.
    const logs = mock.getLogs();
    try expectEqual(@as(usize, 0), logs.len);
}

test "Log snapshot/revert: logs truncated on revert" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    const spec = Spec.forFork(.BYZANTIUM); // REVERT introduced in Byzantium
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    // Contract: LOG0, then REVERT.
    const code = &[_]u8{
        0x60, 0x00, // PUSH1 0 (size)
        0x60, 0x00, // PUSH1 0 (offset)
        0xA0, // LOG0
        0x60, 0x00, // PUSH1 0 (size)
        0x60, 0x00, // PUSH1 0 (offset)
        0xFD, // REVERT
    };
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
    try expectEqual(ExecutionStatus.REVERT, result.status);

    // Verify logs were reverted.
    const logs = mock.getLogs();
    try expectEqual(@as(usize, 0), logs.len);
}

test "LOG gas precision" {
    const TestCase = struct {
        bytecode: []const u8,
        expected_gas: u64,
    };

    const cases = [_]TestCase{
        // offset=0, size=0: PUSH1(3) + PUSH1(3) + LOG0(375) + STOP(0) = 381 * 2 = 756
        .{
            .bytecode = createLog0EmptyData(),
            .expected_gas = 756,
        },
        // offset=0, size=32: PUSH32(3) + PUSH1(3) + MSTORE(6) + PUSH1(3) + PUSH1(3) + LOG0(631) + STOP(0)
        .{
            .bytecode = createLog0WithData(),
            .expected_gas = 1024,
        },
    };

    for (cases) |case| {
        const allocator = std.testing.allocator;
        var env = Env.default();
        var mock = MockHost.init(allocator);
        defer mock.deinit();

        const spec = Spec.forFork(.FRONTIER);
        var evm = Evm.init(allocator, &env, mock.host(), spec);
        defer evm.deinit();

        try mock.setCode(th.SIMPLE_TARGET, case.bytecode);

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
        try expectEqual(case.expected_gas, result.gas_used);
    }
}
