//! Runtime gas accounting for EVM execution.
//!
//! Tracks gas limit, consumption, refunds, and memory costs during execution.
//! All cost calculations are delegated to cost_fns.

const std = @import("std");
const Spec = @import("../../hardfork/spec.zig").Spec;
const cost_fns = @import("cost_fns.zig");

/// EVM gas accounting state.
///
/// Tracks gas usage throughout transaction execution, including:
/// - Gas limit enforcement
/// - Gas consumption tracking
/// - Refund accumulation and capping
/// - Memory expansion costs
pub const Gas = struct {
    /// Gas limit for this execution context
    limit: u64,

    /// Gas consumed so far
    used: u64,

    /// Gas refunded (SSTORE, SELFDESTRUCT, etc.)
    /// Capped per EIP-3529 (refund divisor varies by fork)
    refunded: u64,

    /// Last memory expansion cost (for incremental calculation)
    /// Updated by updateMemoryCost after each expansion
    last_memory_cost: u64,

    /// Hard fork specification (controls gas costs and refund rules)
    spec: Spec,

    /// Gas operation errors
    pub const Error = error{
        OutOfGas,
    };

    /// Initialize gas accounting with given limit and fork specification.
    pub fn init(limit: u64, spec: Spec) Gas {
        return Gas{
            .limit = limit,
            .used = 0,
            .refunded = 0,
            .last_memory_cost = 0,
            .spec = spec,
        };
    }

    /// Consume gas, error if exceeds limit.
    pub fn consume(self: *Gas, amount: u64) Error!void {
        const new_used = self.used + amount;
        if (new_used > self.limit) {
            return error.OutOfGas;
        }
        self.used = new_used;
    }

    /// Get remaining gas.
    pub fn remaining(self: *const Gas) u64 {
        return self.limit - self.used;
    }

    /// Add gas refund.
    ///
    /// Note: The actual refund is capped when finalizing (EIP-3529).
    /// We track the full refund amount here and cap it later.
    pub fn refund(self: *Gas, amount: u64) void {
        self.refunded += amount;
    }

    /// Calculate final refund amount (capped per EIP-3529).
    ///
    /// Refund cap varies by fork (EIP-3529 changed from used/2 to used/5).
    /// This is called after execution to determine actual refund.
    pub fn finalRefund(self: *const Gas) u64 {
        const max_refund = self.used / self.spec.max_refund_quotient;
        return @min(self.refunded, max_refund);
    }

    /// Get gas left after accounting for refund.
    ///
    /// This is the gas returned to the caller.
    pub fn remainingWithRefund(self: *const Gas) u64 {
        return self.remaining() + self.finalRefund();
    }

    /// Calculate memory expansion gas cost (incremental).
    ///
    /// Takes old and new memory sizes from Memory struct.
    /// Returns only the incremental cost (new_cost - last_cost).
    pub fn memoryExpansionCost(self: *const Gas, old_size: usize, new_size: usize) u64 {
        if (new_size <= old_size) {
            return 0;
        }

        return cost_fns.memoryCost(new_size) - self.last_memory_cost;
    }

    /// Update last memory cost after successful expansion.
    ///
    /// Called by interpreter after gas is charged and memory expanded.
    pub fn updateMemoryCost(self: *Gas, memory_size: usize) void {
        self.last_memory_cost = cost_fns.memoryCost(memory_size);
    }
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Gas: init" {
    const test_cases = [_]struct {
        limit: u64,
        spec: Spec,
    }{
        .{ .limit = 1000, .spec = Spec.forFork(.CANCUN) },
        .{ .limit = 21000, .spec = Spec.forFork(.LONDON) },
        .{ .limit = 0, .spec = Spec.forFork(.FRONTIER) },
    };

    for (test_cases) |tc| {
        const gas = Gas.init(tc.limit, tc.spec);
        try expectEqual(tc.limit, gas.limit);
        try expectEqual(@as(u64, 0), gas.used);
        try expectEqual(@as(u64, 0), gas.refunded);
        try expectEqual(@as(u64, 0), gas.last_memory_cost);
    }
}

test "Gas: consume" {
    const test_cases = [_]struct {
        limit: u64,
        consumes: []const u64,
        expected_error: ?Gas.Error,
        expected_used: u64,
        expected_remaining: u64,
    }{
        // Within limit
        .{
            .limit = 1000,
            .consumes = &[_]u64{300},
            .expected_error = null,
            .expected_used = 300,
            .expected_remaining = 700,
        },
        // Exactly at limit
        .{
            .limit = 1000,
            .consumes = &[_]u64{1000},
            .expected_error = null,
            .expected_used = 1000,
            .expected_remaining = 0,
        },
        // Exceeds limit
        .{
            .limit = 1000,
            .consumes = &[_]u64{1001},
            .expected_error = error.OutOfGas,
            .expected_used = 0,
            .expected_remaining = 1000,
        },
        // Multiple consume operations
        .{
            .limit = 1000,
            .consumes = &[_]u64{ 100, 200, 300 },
            .expected_error = null,
            .expected_used = 600,
            .expected_remaining = 400,
        },
        // Multiple operations hitting limit
        .{
            .limit = 1000,
            .consumes = &[_]u64{ 500, 500 },
            .expected_error = null,
            .expected_used = 1000,
            .expected_remaining = 0,
        },
        // Multiple operations exceeding limit
        .{
            .limit = 1000,
            .consumes = &[_]u64{ 500, 501 },
            .expected_error = error.OutOfGas,
            .expected_used = 500,
            .expected_remaining = 500,
        },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(.CANCUN);
        var gas = Gas.init(tc.limit, spec);

        var had_error = false;
        for (tc.consumes) |amount| {
            gas.consume(amount) catch |err| {
                if (tc.expected_error) |expected_err| {
                    try expectEqual(expected_err, err);
                    had_error = true;
                    break;
                } else {
                    return err;
                }
            };
        }

        if (tc.expected_error != null) {
            try expect(had_error);
        }

        try expectEqual(tc.expected_used, gas.used);
        try expectEqual(tc.expected_remaining, gas.remaining());
    }
}

test "Gas: refund" {
    const test_cases = [_]struct {
        spec: Spec,
        limit: u64,
        consume_amount: u64,
        refund_amounts: []const u64,
        expected_refunded: u64,
        expected_final_refund: u64,
        expected_remaining_with_refund: u64,
    }{
        // Multiple refunds
        .{
            .spec = Spec.forFork(.CANCUN),
            .limit = 1000,
            .consume_amount = 500,
            .refund_amounts = &[_]u64{ 100, 50 },
            .expected_refunded = 150,
            .expected_final_refund = 100, // Capped at 500/5 = 100
            .expected_remaining_with_refund = 600, // 500 remaining + 100 refund
        },
        // Refund capping (EIP-3529, quotient = 5)
        .{
            .spec = Spec.forFork(.CANCUN),
            .limit = 10000,
            .consume_amount = 5000,
            .refund_amounts = &[_]u64{2000},
            .expected_refunded = 2000,
            .expected_final_refund = 1000, // Capped at 5000/5 = 1000
            .expected_remaining_with_refund = 6000, // 5000 remaining + 1000 refund
        },
        // Refund within cap
        .{
            .spec = Spec.forFork(.CANCUN),
            .limit = 10000,
            .consume_amount = 5000,
            .refund_amounts = &[_]u64{1000},
            .expected_refunded = 1000,
            .expected_final_refund = 1000, // Within cap of 5000/5 = 1000
            .expected_remaining_with_refund = 6000, // 5000 remaining + 1000 refund
        },
        // Pre-EIP-3529: refund cap is used/2
        .{
            .spec = Spec.forFork(.BERLIN),
            .limit = 10000,
            .consume_amount = 5000,
            .refund_amounts = &[_]u64{3000},
            .expected_refunded = 3000,
            .expected_final_refund = 2500, // Capped at 5000/2 = 2500
            .expected_remaining_with_refund = 7500, // 5000 remaining + 2500 refund
        },
    };

    for (test_cases) |tc| {
        var gas = Gas.init(tc.limit, tc.spec);
        try gas.consume(tc.consume_amount);

        for (tc.refund_amounts) |amount| {
            gas.refund(amount);
        }

        try expectEqual(tc.expected_refunded, gas.refunded);
        try expectEqual(tc.expected_final_refund, gas.finalRefund());
        try expectEqual(tc.expected_remaining_with_refund, gas.remainingWithRefund());
    }
}

test "Gas: memory expansion cost" {
    const MemoryOp = struct {
        old_size: usize,
        new_size: usize,
        expected_cost: u64,
    };

    const test_cases = [_]struct {
        limit: u64,
        ops: []const MemoryOp,
    }{
        // First expansion (0 -> 32)
        // cost = 1^2/512 + 3*1 = 0 + 3 = 3 gas
        .{
            .limit = 100000,
            .ops = &[_]MemoryOp{
                .{ .old_size = 0, .new_size = 32, .expected_cost = 3 },
            },
        },
        // Incremental expansion (0 -> 32, then 32 -> 64)
        // First: cost = 3 gas
        // Second: cost = 2^2/512 + 3*2 = 6 gas, incremental = 6 - 3 = 3 gas
        .{
            .limit = 100000,
            .ops = &[_]MemoryOp{
                .{ .old_size = 0, .new_size = 32, .expected_cost = 3 },
                .{ .old_size = 32, .new_size = 64, .expected_cost = 3 },
            },
        },
        // No expansion - shrink (64 -> 32)
        .{
            .limit = 100000,
            .ops = &[_]MemoryOp{
                .{ .old_size = 0, .new_size = 64, .expected_cost = 6 },
                .{ .old_size = 64, .new_size = 32, .expected_cost = 0 },
            },
        },
        // No expansion - same size (64 -> 64)
        .{
            .limit = 100000,
            .ops = &[_]MemoryOp{
                .{ .old_size = 0, .new_size = 64, .expected_cost = 6 },
                .{ .old_size = 64, .new_size = 64, .expected_cost = 0 },
            },
        },
        // Quadratic growth (0 -> 1024)
        // 1024 bytes = 32 words
        // cost = 32^2/512 + 3*32 = 2 + 96 = 98 gas
        .{
            .limit = 1000000,
            .ops = &[_]MemoryOp{
                .{ .old_size = 0, .new_size = 1024, .expected_cost = 98 },
            },
        },
        // Zero size (0 -> 0)
        .{
            .limit = 100000,
            .ops = &[_]MemoryOp{
                .{ .old_size = 0, .new_size = 0, .expected_cost = 0 },
            },
        },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(.CANCUN);
        var gas = Gas.init(tc.limit, spec);

        for (tc.ops, 0..) |op, i| {
            const cost = gas.memoryExpansionCost(op.old_size, op.new_size);
            try expectEqual(op.expected_cost, cost);

            // Update after each op except the last
            if (i < tc.ops.len - 1) {
                gas.updateMemoryCost(op.new_size);
            }
        }
    }
}
