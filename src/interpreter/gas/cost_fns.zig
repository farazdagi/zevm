//! Gas cost calculation functions.
//!
//! This module contains all gas cost calculations that depend on:
//! - Fork specifications (via Spec parameter)
//! - Operation parameters (size, count, flags, etc.)
//!
//! All functions are pure - they don't modify state and always return
//! the same result for the same inputs.
//!
//! ## Overflow Safety
//!
//! All arithmetic uses saturating operations (+|, *|) to prevent overflow.
//! Rationale: Any gas cost exceeding u64 max (~1.8*10^19) is orders of
//! magnitude beyond the block gas limit (~3*10^7) and indicates either a bug
//! or malicious input. Saturating ensures such cases are safely rejected.

const spec_mod = @import("../../hardfork/spec.zig");
const Spec = spec_mod.Spec;
const Costs = @import("costs.zig").Costs;

/// Calculate total memory cost for given byte size.
///
/// Quadratic cost: words^2 / 512 + 3 * words
pub fn memoryCost(byte_size: usize) u64 {
    if (byte_size == 0) return 0;

    // Round up to word size (32 bytes)
    const words = (byte_size +| 31) / 32;

    // Quadratic cost: words^2 / 512 + 3 * words
    return (words *| words) / 512 +| Costs.MEMORY *| words;
}

/// Get account access cost (BALANCE, EXTCODESIZE, EXTCODECOPY, EXTCODEHASH).
///
/// Handles both pre-Berlin (flat cost, no cold/warm distinction) and post-Berlin (cold/warm) models.
///
/// Pre-Berlin: Returns Spec.cold_account_access_cost regardless of is_cold
/// Post-Berlin+: Returns 2600 (cold) or 100 (warm)
///
/// EIPs: EIP-150 (Tangerine), EIP-2929 (Berlin)
pub fn accountAccessCost(spec: Spec, is_cold: bool) u64 {
    if (is_cold or spec.fork.isBefore(.BERLIN)) {
        return spec.cold_account_access_cost;
    }
    return spec.warm_storage_read_cost;
}

/// Get CALL base cost (CALL, DELEGATECALL, STATICCALL).
///
/// Evolution:
/// - Pre-Tangerine: 40 gas
/// - Tangerine to Berlin: 700 gas
/// - Post-Berlin: 2600 (cold) or 100 (warm)
///
/// EIPs: EIP-150 (Tangerine), EIP-2929 (Berlin)
pub fn callBaseCost(spec: Spec, is_cold: bool) u64 {
    // Pre-Berlin: flat cost
    if (spec.fork.isBefore(.BERLIN)) {
        return if (spec.fork.isBefore(.TANGERINE)) 40 else 700;
    }

    // Post-Berlin: cold/warm model
    return if (is_cold) spec.cold_account_access_cost else spec.warm_storage_read_cost;
}

/// Get SLOAD cost.
///
/// Evolution:
/// - Frontier-Tangerine: 50 gas
/// - Tangerine-Istanbul: 200 gas
/// - Istanbul-Berlin: 800 gas
/// - Post-Berlin: 2100 (cold) or 100 (warm)
///
/// EIPs: EIP-150 (Tangerine), EIP-1884 (Istanbul), EIP-2929 (Berlin)
pub fn sloadCost(spec: Spec, is_cold: bool) u64 {
    if (spec.fork.isBefore(.BERLIN)) {
        // No cold/warm distinction
        return spec.cold_sload_cost;
    }

    return if (is_cold) spec.cold_sload_cost else spec.warm_storage_read_cost;
}

// TODO: sstoreCost() deferred - requires full EIP-2200 state transition logic
// Will be added when implementing SSTORE opcode

/// Calculate EXP gas cost based on exponent byte length.
///
/// Handles EIP-160 change:
/// - Pre-Spurious Dragon: 10 + (10 * bytes)
/// - Post-Spurious Dragon: 10 + (50 * bytes)
///
/// EIPs: EIP-160 (Spurious Dragon)
pub fn expCost(spec: Spec, exponent_byte_size: u8) u64 {
    const base = Costs.EXP_BASE;
    const per_byte: u64 = if (spec.fork.isBefore(.SPURIOUS_DRAGON)) 10 else 50;
    return base +| (per_byte *| @as(u64, exponent_byte_size));
}

/// Calculate calldata gas cost for given data.
///
/// Handles EIP-2028 change:
/// - Pre-Istanbul: 4/zero-byte, 68/non-zero byte
/// - Post-Istanbul: 4/zero-byte, 16/non-zero byte
/// EIPs: EIP-2028 (Istanbul)
pub fn calldataCost(spec: Spec, data: []const u8) u64 {
    const calldata_nonzero_cost: u64 = if (spec.fork.isBefore(.ISTANBUL)) 68 else 16;
    var cost: u64 = 0;
    for (data) |byte| {
        cost +|= if (byte == 0) Costs.CALLDATA_ZERO_COST else calldata_nonzero_cost;
    }
    return cost;
}

/// Calculate cost for copy operations (CALLDATACOPY, CODECOPY, etc.).
///
/// Formula: base + (word_cost * ceil(size/32))
///
/// Examples:
/// - CALLDATACOPY: copyCost(3, 3, size)
/// - CODECOPY: copyCost(3, 3, size)
/// - RETURNDATACOPY: copyCost(3, 3, size)
///
/// EIPs: Yellow Paper (Frontier), EIP-211 (Byzantium - RETURNDATACOPY)
pub fn copyCost(base: u64, word_cost: u64, size: usize) u64 {
    const words = (size +| 31) / 32;
    return base +| (word_cost *| @as(u64, @intCast(words)));
}

/// Calculate KECCAK256 (SHA3) cost based on input size.
///
/// Formula: 30 + (6 * ceil(size/32))
pub fn keccak256Cost(size: usize) u64 {
    const words = (size +| 31) / 32;
    return Costs.KECCAK256_BASE +| (Costs.KECCAK256_WORD *| @as(u64, @intCast(words)));
}

/// Calculate LOG cost (LOG0-LOG4).
///
/// Formula: 375 + (375 * topic_count) + (8 * data_size_bytes)
pub fn logCost(topic_count: u8, data_size: usize) u64 {
    const topics = @as(u64, topic_count);
    const bytes = @as(u64, @intCast(data_size));
    return Costs.LOG_BASE +| (Costs.LOG_TOPIC *| topics) +| (Costs.LOG_DATA *| bytes);
}

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "memoryCost" {
    const test_cases = [_]struct {
        byte_size: usize,
        expected: u64,
    }{
        // Zero size
        .{ .byte_size = 0, .expected = 0 },
        // 1 word: (1^2/512) + (3*1) = 3
        .{ .byte_size = 32, .expected = 3 },
        // 2 words: (2^2/512) + (3*2) = 6
        .{ .byte_size = 64, .expected = 6 },
        // 32 words: (32^2/512) + (3*32) = 98
        .{ .byte_size = 1024, .expected = 98 },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, memoryCost(tc.byte_size));
    }
}

test "accountAccessCost - pre-Berlin" {
    const homestead_spec = Spec.forFork(.HOMESTEAD);

    // Pre-Berlin: always returns cold_account_access_cost
    try expectEqual(@as(u64, 700), accountAccessCost(homestead_spec, true));
    try expectEqual(@as(u64, 700), accountAccessCost(homestead_spec, false));
}

test "accountAccessCost - Berlin+" {
    const berlin_spec = Spec.forFork(.BERLIN);

    // Berlin+: cold = 2600, warm = 100
    try expectEqual(@as(u64, 2600), accountAccessCost(berlin_spec, true));
    try expectEqual(@as(u64, 100), accountAccessCost(berlin_spec, false));
}

test "callBaseCost - evolution" {
    const frontier_spec = Spec.forFork(.FRONTIER);
    const tangerine_spec = Spec.forFork(.TANGERINE);
    const berlin_spec = Spec.forFork(.BERLIN);

    // Pre-Tangerine: 40
    try expectEqual(@as(u64, 40), callBaseCost(frontier_spec, true));
    try expectEqual(@as(u64, 40), callBaseCost(frontier_spec, false));

    // Tangerine-Berlin: 700
    try expectEqual(@as(u64, 700), callBaseCost(tangerine_spec, true));
    try expectEqual(@as(u64, 700), callBaseCost(tangerine_spec, false));

    // Berlin+: 2600 (cold) or 100 (warm)
    try expectEqual(@as(u64, 2600), callBaseCost(berlin_spec, true));
    try expectEqual(@as(u64, 100), callBaseCost(berlin_spec, false));
}

test "sloadCost - evolution" {
    const homestead_spec = Spec.forFork(.HOMESTEAD);
    const berlin_spec = Spec.forFork(.BERLIN);

    // Pre-Berlin: no cold/warm distinction
    try expectEqual(@as(u64, 200), sloadCost(homestead_spec, true));
    try expectEqual(@as(u64, 200), sloadCost(homestead_spec, false));

    // Berlin+: 2100 (cold) or 100 (warm)
    try expectEqual(@as(u64, 2100), sloadCost(berlin_spec, true));
    try expectEqual(@as(u64, 100), sloadCost(berlin_spec, false));
}

test "expCost" {
    const test_cases = [_]struct {
        spec: Spec,
        exponent_byte_size: u8,
        expected: u64,
    }{
        // Pre-Spurious Dragon: 0 bytes
        .{ .spec = Spec.forFork(.FRONTIER), .exponent_byte_size = 0, .expected = 10 },
        // Pre-Spurious Dragon: 2 bytes
        .{ .spec = Spec.forFork(.FRONTIER), .exponent_byte_size = 2, .expected = 30 },
        // Pre-Spurious Dragon: 32 bytes (max)
        .{ .spec = Spec.forFork(.FRONTIER), .exponent_byte_size = 32, .expected = 330 },
        // Post-Spurious Dragon: 0 bytes
        .{ .spec = Spec.forFork(.SPURIOUS_DRAGON), .exponent_byte_size = 0, .expected = 10 },
        // Post-Spurious Dragon: 2 bytes
        .{ .spec = Spec.forFork(.SPURIOUS_DRAGON), .exponent_byte_size = 2, .expected = 110 },
        // Post-Spurious Dragon: 32 bytes (max)
        .{ .spec = Spec.forFork(.SPURIOUS_DRAGON), .exponent_byte_size = 32, .expected = 1610 },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, expCost(tc.spec, tc.exponent_byte_size));
    }
}

test "calldataCost" {
    const byzantium_spec = Spec.forFork(.BYZANTIUM);
    const istanbul_spec = Spec.forFork(.ISTANBUL);
    const berlin_spec = Spec.forFork(.BERLIN);

    const data1 = [_]u8{ 0, 0, 0, 1 }; // 3 zeros, 1 non-zero
    const data2 = [_]u8{ 1, 2, 3, 4 }; // All non-zero
    const data3 = [_]u8{ 0, 0, 0, 0 }; // All zeros

    // Pre-Istanbul: 4/zero, 68/non-zero
    try expectEqual(@as(u64, 3 * 4 + 1 * 68), calldataCost(byzantium_spec, &data1));
    try expectEqual(@as(u64, 4 * 68), calldataCost(byzantium_spec, &data2));
    try expectEqual(@as(u64, 4 * 4), calldataCost(byzantium_spec, &data3));

    // Istanbul+: 4/zero, 16/non-zero
    try expectEqual(@as(u64, 3 * 4 + 1 * 16), calldataCost(istanbul_spec, &data1));
    try expectEqual(@as(u64, 4 * 16), calldataCost(istanbul_spec, &data2));
    try expectEqual(@as(u64, 4 * 4), calldataCost(istanbul_spec, &data3));

    // Istanbul+: 4/zero, 16/non-zero
    try expectEqual(@as(u64, 3 * 4 + 1 * 16), calldataCost(berlin_spec, &data1));
    try expectEqual(@as(u64, 4 * 16), calldataCost(berlin_spec, &data2));
    try expectEqual(@as(u64, 4 * 4), calldataCost(berlin_spec, &data3));
}

test "copyCost" {
    const test_cases = [_]struct {
        base: u64,
        word_cost: u64,
        size: usize,
        expected: u64,
    }{
        // 100 bytes = 4 words
        .{ .base = 3, .word_cost = 3, .size = 100, .expected = 15 },
        // 32 bytes = 1 word
        .{ .base = 3, .word_cost = 3, .size = 32, .expected = 6 },
        // 0 bytes
        .{ .base = 3, .word_cost = 3, .size = 0, .expected = 3 },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, copyCost(tc.base, tc.word_cost, tc.size));
    }
}

test "keccak256Cost" {
    const test_cases = [_]struct {
        size: usize,
        expected: u64,
    }{
        // 100 bytes = 4 words: 30 + 6*4 = 54
        .{ .size = 100, .expected = 54 },
        // 32 bytes = 1 word: 30 + 6 = 36
        .{ .size = 32, .expected = 36 },
        // 0 bytes: 30 + 0 = 30
        .{ .size = 0, .expected = 30 },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, keccak256Cost(tc.size));
    }
}

test "logCost" {
    const test_cases = [_]struct {
        topic_count: u8,
        data_size: usize,
        expected: u64,
    }{
        // LOG2: 375 + 375*2 + 8*100 = 1925
        .{ .topic_count = 2, .data_size = 100, .expected = 1925 },
        // LOG0: 375 + 0 + 8*100 = 1175
        .{ .topic_count = 0, .data_size = 100, .expected = 1175 },
        // LOG4: 375 + 375*4 + 8*256 = 3923
        .{ .topic_count = 4, .data_size = 256, .expected = 3923 },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, logCost(tc.topic_count, tc.data_size));
    }
}

test "overflow saturation" {
    // This test verifies that saturating arithmetic (+|, *|) prevents overflow.
    // If someone accidentally removes the | operators, these tests will catch it.
    // We verify that extreme inputs produce very large results or max_u64.
    const max_u64 = std.math.maxInt(u64);
    const threshold = max_u64 / 1024; // Threshold for "very large" result

    // memoryCost: quadratic term overflows with large input
    // With huge input, words^2 saturates, then /512, result is still huge
    const huge_size: usize = if (@sizeOf(usize) >= 8) (1 << 40) else (1 << 20);
    const memory_result = memoryCost(huge_size);
    try expect(memory_result > threshold);

    // copyCost: multiplication saturates
    // (max_u64 / 2) * 3 = 1.5 * max_u64, saturates to max_u64
    const copy_result = copyCost(0, max_u64 / 2, 96); // 96 bytes = 3 words
    try expect(copy_result == max_u64);

    // copyCost: addition saturates to exactly max_u64
    const copy_result2 = copyCost(max_u64 - 100, 200, 32);
    try expect(copy_result2 == max_u64);

    // keccak256Cost: multiplier (6) is small, need very large size
    // Need size such that 6 * (size/32) > threshold, so size > threshold / 192
    // Use max_u64 / 8 to ensure we exceed threshold
    const keccak_huge: usize = if (@sizeOf(usize) >= 8) max_u64 / 8 else (1 << 28);
    const keccak_result = keccak256Cost(keccak_huge);
    try expect(keccak_result > threshold);

    // logCost: data size multiplication saturates
    // 8 * (max_u64 / 4) = 2 * max_u64, overflows to max_u64
    const very_large_size: usize = max_u64 / 4;
    const log_result = logCost(4, very_large_size);
    try expect(log_result == max_u64);

    // Note: calldataCost accumulation overflow is impractical to test
    // (would require ~270 PB allocation). The +|= operator is verified
    // by inspection and smaller tests verify the logic is correct.
}
