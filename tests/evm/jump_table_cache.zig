//! Tests for JumpTable caching functionality.
//!
//! Verifies that bytecode analysis is cached by code hash
//! and reused across multiple calls to the same contract.

const std = @import("std");
const th = @import("test_helpers.zig");

const Evm = th.Evm;
const Env = th.Env;
const Spec = th.Spec;
const Address = th.Address;
const U256 = th.U256;
const CallInputs = th.CallInputs;
const ExecutionStatus = th.ExecutionStatus;
const MockHost = th.MockHost;

const expectEqual = th.expectEqual;

const Contract = struct {
    address_suffix: u8,
    bytecode: []const u8,
};

const Call = struct {
    target_suffix: u8,
    expected_status: ExecutionStatus,
};

const TestCase = struct {
    contracts: []const Contract,
    calls: []const Call,
    expected_cache_count: usize,
};

fn runTestCase(tc: TestCase) !void {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    // Deploy contracts.
    for (tc.contracts) |contract| {
        var addr_bytes = [_]u8{0} ** 20;
        addr_bytes[19] = contract.address_suffix;
        const target = Address.init(addr_bytes);
        try mock.setCode(target, contract.bytecode);
    }

    // Execute calls.
    for (tc.calls) |call| {
        var addr_bytes = [_]u8{0} ** 20;
        addr_bytes[19] = call.target_suffix;
        const target = Address.init(addr_bytes);

        const inputs = CallInputs{
            .kind = .CALL,
            .target = target,
            .caller = Address.zero(),
            .value = U256.ZERO,
            .input = &[_]u8{},
            .gas_limit = 100000,
            .transfer_value = false,
        };

        const result = try evm.call(inputs);
        try expectEqual(call.expected_status, result.status);
    }

    // Verify cache count.
    try expectEqual(tc.expected_cache_count, evm.jump_table_cache.count());
}

test "JumpTable cache" {
    const test_cases = [_]TestCase{
        // Cache hit on same bytecode: two calls to same contract should result in one cache entry.
        .{
            .contracts = &[_]Contract{
                .{ .address_suffix = 1, .bytecode = &[_]u8{ 0x5B, 0x00 } }, // JUMPDEST, STOP
            },
            .calls = &[_]Call{
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
            },
            .expected_cache_count = 1,
        },
        // Different bytecode creates separate entries.
        .{
            .contracts = &[_]Contract{
                .{ .address_suffix = 1, .bytecode = &[_]u8{ 0x5B, 0x00 } }, // JUMPDEST, STOP
                .{ .address_suffix = 2, .bytecode = &[_]u8{ 0x60, 0x01, 0x00 } }, // PUSH1 0x01, STOP
            },
            .calls = &[_]Call{
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
                .{ .target_suffix = 2, .expected_status = .SUCCESS },
            },
            .expected_cache_count = 2,
        },
        // Same code at different addresses shares cache.
        .{
            .contracts = &[_]Contract{
                .{ .address_suffix = 1, .bytecode = &[_]u8{ 0x5B, 0x00 } }, // JUMPDEST, STOP
                .{ .address_suffix = 2, .bytecode = &[_]u8{ 0x5B, 0x00 } }, // Same bytecode
            },
            .calls = &[_]Call{
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
                .{ .target_suffix = 2, .expected_status = .SUCCESS },
            },
            .expected_cache_count = 1,
        },
        // Cached jump table validates jumps correctly: PUSH1 0x04, JUMP, INVALID, JUMPDEST, STOP.
        .{
            .contracts = &[_]Contract{
                .{ .address_suffix = 1, .bytecode = &[_]u8{ 0x60, 0x04, 0x56, 0xFE, 0x5B, 0x00 } },
            },
            .calls = &[_]Call{
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
            },
            .expected_cache_count = 1,
        },
        // Invalid jump detected with cached table: PUSH1 0x03, JUMP, INVALID, STOP.
        .{
            .contracts = &[_]Contract{
                .{ .address_suffix = 1, .bytecode = &[_]u8{ 0x60, 0x03, 0x56, 0x00 } },
            },
            .calls = &[_]Call{
                .{ .target_suffix = 1, .expected_status = .INVALID_JUMP },
                .{ .target_suffix = 1, .expected_status = .INVALID_JUMP },
            },
            .expected_cache_count = 1,
        },
        // Empty bytecode: doesn't get cached.
        .{
            .contracts = &[_]Contract{
                .{ .address_suffix = 1, .bytecode = &[_]u8{} },
            },
            .calls = &[_]Call{
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
            },
            .expected_cache_count = 0,
        },
        // DeFi pattern: 4 repeated calls to same contract should result in one cache entry.
        .{
            .contracts = &[_]Contract{
                .{ .address_suffix = 1, .bytecode = &[_]u8{ 0x5B, 0x00 } }, // JUMPDEST, STOP
            },
            .calls = &[_]Call{
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
                .{ .target_suffix = 1, .expected_status = .SUCCESS },
            },
            .expected_cache_count = 1,
        },
    };

    for (test_cases) |tc| {
        try runTestCase(tc);
    }
}
