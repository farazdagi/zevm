//! SSTORE gas cost and refund calculations.
//!
//! This module provides pure functions for calculating SSTORE gas costs and refunds.
//! These are called from the opSstore handler AFTER host.sstore() performs the write.
//! In that sense, sstore opcode is special, gas is charged after the store operation,
//! however, it doesn't invalidate the core variant -- no commit without enough gas --
//! since on out of gas error, opcode handler aborts with error, and state is reverted.
//! So, since SSTORE uses state snapshots, the actual operation doesn't persist unless
//! enough gas is paid.
//!
//! Gas rules across forks:
//! Frontier-Byzantium: Simple set/reset model
//! Istanbul (EIP-2200): Net gas metering with original/current/new tracking
//! Berlin (EIP-2929): Added cold/warm access costs
//! London (EIP-3529): Reduced refunds

const std = @import("std");
const Spec = @import("../hardfork.zig").Spec;
const Hardfork = @import("../hardfork.zig").Hardfork;
const U256 = @import("../primitives/big.zig").U256;
const Host = @import("../host/Host.zig");

/// Calculate SSTORE gas cost.
///
/// Called from opSstore handler AFTER `host.sstore()` writes and returns info.
/// The `is_cold` parameter comes from `AccessList.warmSlot()`.
///
/// Returns the gas cost to charge for this SSTORE operation.
pub fn sstoreCost(spec: Spec, result: Host.SstoreResult, new_value: U256, is_cold: bool) u64 {
    const original = result.original_value;
    const current = result.current_value;

    // Cold access cost (Berlin+, EIP-2929).
    const cold_cost: u64 = if (spec.fork.isAtLeast(.BERLIN) and is_cold) spec.cold_sload_cost else 0;

    // Pre-Istanbul: Simple set/reset model.
    if (spec.fork.isBefore(.ISTANBUL)) {
        if (current.isZero() and !new_value.isZero()) {
            // Zero -> non-zero: SET
            return spec.sstore_set_gas +| cold_cost;
        } else {
            // Non-zero -> anything: RESET
            return spec.sstore_reset_gas +| cold_cost;
        }
    }

    // Istanbul+ (EIP-2200): Net gas metering.
    // Base cost depends on whether this is a "no-op", first change, or subsequent change.

    if (current.eql(new_value)) {
        // No-op: value unchanged.
        return spec.sload_gas +| cold_cost;
    }

    if (original.eql(current)) {
        // First change in this transaction.
        if (original.isZero()) {
            // Zero -> non-zero: SET
            return spec.sstore_set_gas +| cold_cost;
        } else {
            // Non-zero -> different non-zero, or non-zero -> zero.
            // Berlin+ uses reduced reset cost (5000 - 2100 = 2900).
            const reset_cost = if (spec.fork.isAtLeast(.BERLIN))
                spec.sstore_reset_gas - spec.cold_sload_cost
            else
                spec.sstore_reset_gas;
            return reset_cost +| cold_cost;
        }
    }

    // Subsequent change (original != current): cheap update.
    return spec.sload_gas +| cold_cost;
}

/// Calculate SSTORE refund.
///
/// Called from opSstore handler after gas is charged.
/// Returns a signed value: positive for refund, negative for removing previously granted refund.
pub fn sstoreRefund(spec: Spec, result: Host.SstoreResult, new_value: U256) i64 {
    const original = result.original_value;
    const current = result.current_value;

    // Pre-Istanbul: Simple refund model.
    if (spec.fork.isBefore(.ISTANBUL)) {
        // Refund only when clearing storage (non-zero -> zero).
        if (!current.isZero() and new_value.isZero()) {
            return @intCast(spec.sstore_clears_schedule);
        }
        return 0;
    }

    // Istanbul+ (EIP-2200): Net gas metering refunds.
    var refund: i64 = 0;

    if (current.eql(new_value)) {
        // No-op: no refund.
        return 0;
    }

    if (original.eql(current)) {
        // First change in transaction.
        if (!original.isZero() and new_value.isZero()) {
            // Clearing storage: non-zero -> zero.
            refund += @intCast(spec.sstore_clears_schedule);
        }
    } else {
        // Subsequent change (original != current).

        // Case: Restoring to original value.
        if (!original.isZero()) {
            if (current.isZero()) {
                // Was cleared, now restoring: remove the clear refund.
                refund -= @intCast(spec.sstore_clears_schedule);
            } else if (new_value.isZero()) {
                // Now clearing: add clear refund.
                refund += @intCast(spec.sstore_clears_schedule);
            }
        }

        // Restore bonus: if restoring to original value, refund the difference.
        if (original.eql(new_value)) {
            if (original.isZero()) {
                // Restoring to zero from SET: refund SET - SLOAD_GAS.
                const set_refund = spec.sstore_set_gas - spec.sload_gas;
                refund += @intCast(set_refund);
            } else {
                // Restoring to non-zero: refund RESET - warm_read.
                const reset_cost = if (spec.fork.isAtLeast(.BERLIN))
                    spec.sstore_reset_gas - spec.cold_sload_cost
                else
                    spec.sstore_reset_gas;
                const reset_refund = reset_cost - spec.sload_gas;
                refund += @intCast(reset_refund);
            }
        }
    }

    return refund;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const expectEqual = testing.expectEqual;

fn makeResult(original: u64, current: u64) Host.SstoreResult {
    return .{
        .original_value = U256.fromU64(original),
        .current_value = U256.fromU64(current),
    };
}

test "SSTORE gas costs" {
    const test_cases = [_]struct {
        fork: Hardfork,
        original: u64,
        current: u64,
        new_value: u64,
        is_cold: bool,
        expected_gas: u64,
    }{
        // Istanbul: Zero to non-zero (SET)
        .{
            .fork = .ISTANBUL,
            .original = 0,
            .current = 0,
            .new_value = 1,
            .is_cold = false,
            .expected_gas = 20000,
        },

        // Istanbul: Non-zero to different non-zero (RESET)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 1,
            .new_value = 2,
            .is_cold = false,
            .expected_gas = 5000,
        },

        // Istanbul: Non-zero to zero (CLEAR)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 1,
            .new_value = 0,
            .is_cold = false,
            .expected_gas = 5000,
        },

        // Istanbul: No-op (same value, warm read cost)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 1,
            .new_value = 1,
            .is_cold = false,
            .expected_gas = 800,
        },

        // Istanbul: Net metering - subsequent change (restore to original)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 2,
            .new_value = 1,
            .is_cold = false,
            .expected_gas = 800,
        },

        // Berlin: SET with cold access (adds 2100)
        .{
            .fork = .BERLIN,
            .original = 0,
            .current = 0,
            .new_value = 1,
            .is_cold = true,
            .expected_gas = 22100,
        },

        // Berlin: SET with warm access (no cold cost)
        .{
            .fork = .BERLIN,
            .original = 0,
            .current = 0,
            .new_value = 1,
            .is_cold = false,
            .expected_gas = 20000,
        },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        const result = makeResult(tc.original, tc.current);
        const new_value = if (tc.new_value == 0) U256.ZERO else U256.fromU64(tc.new_value);

        const gas = sstoreCost(spec, result, new_value, tc.is_cold);
        try expectEqual(tc.expected_gas, gas);
    }
}

test "SSTORE refund calculations" {
    const test_cases = [_]struct {
        fork: Hardfork,
        original: u64,
        current: u64,
        new_value: u64,
        expected_refund: i64,
    }{
        // Istanbul: Clear storage (non-zero to zero, get clear refund)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 1,
            .new_value = 0,
            .expected_refund = 15000,
        },

        // London: Clear storage with reduced refund (EIP-3529)
        .{
            .fork = .LONDON,
            .original = 1,
            .current = 1,
            .new_value = 0,
            .expected_refund = 4800,
        },

        // Istanbul: Restore to original non-zero value (restore bonus)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 2,
            .new_value = 1,
            .expected_refund = 4200,
        },

        // Istanbul: Clear then restore (anti-refund: -15000 clear removal + 4200 restore bonus)
        .{
            .fork = .ISTANBUL,
            .original = 1,
            .current = 0,
            .new_value = 1,
            .expected_refund = -10800,
        },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        const result = makeResult(tc.original, tc.current);
        const new_value = if (tc.new_value == 0) U256.ZERO else U256.fromU64(tc.new_value);

        const refund = sstoreRefund(spec, result, new_value);
        try expectEqual(tc.expected_refund, refund);
    }
}
