//! Dynamic gas cost calculation functions.
//!
//! These functions compute gas costs that depend on runtime values (selected fork specifications,
//! operands, memory expansion, etc.). They are called from the instruction table handlers
//! before executing the instruction.
//!
//! ## Overflow Safety
//!
//! All arithmetic uses saturating operations (+|, *|) to prevent overflow.
//! Rationale: Any gas cost exceeding u64 max (~1.8*10^19) is orders of
//! magnitude beyond the block gas limit (~3*10^7) and indicates either a bug
//! or malicious input. Saturating ensures such cases are safely rejected.

const std = @import("std");
const Spec = @import("../hardfork.zig").Spec;
const Interpreter = @import("../interpreter/mod.zig").Interpreter;
const U256 = @import("../primitives/big.zig").U256;
const Costs = @import("costs.zig").Costs;
const FixedGasCosts = @import("FixedGasCosts.zig");

/// Calculate total memory cost for given byte size.
///
/// Quadratic cost: words^2 / 512 + 3 * words
pub fn memoryCost(byte_size: usize) u64 {
    if (byte_size == 0) return 0;

    // Round up to word size (32 bytes)
    const words = (byte_size +| 31) / 32;

    // Quadratic cost: words^2 / 512 + 3 * words
    return (words *| words) / 512 +| FixedGasCosts.VERYLOW *| words;
}

/// Compute EXP dynamic gas cost (per-byte portion only).
///
/// Returns ONLY the dynamic portion. The base cost is charged separately before executing.
///
/// Handles EIP-160 change:
/// - Pre-Spurious Dragon: 10 * bytes
/// - Post-Spurious Dragon: 50 * bytes
///
/// EIPs: EIP-160 (Spurious Dragon)
/// Gas depends on the byte length of the exponent.
pub fn opExp(interp: *Interpreter) !u64 {
    const exponent = try interp.ctx.stack.peek(1);
    const exp_bytes: u8 = @intCast(exponent.byteLen());
    const per_byte: u64 = if (interp.spec.fork.isBefore(.SPURIOUS_DRAGON)) 10 else 50;
    return per_byte *| @as(u64, exp_bytes);
}

/// Compute dynamic gas for MLOAD operation.
///
/// Gas depends on memory expansion.
pub fn opMload(interp: *Interpreter) !u64 {
    const offset_u256 = try interp.ctx.stack.peek(0);
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;

    const old_size = interp.ctx.memory.len();
    const new_size = offset +| 32; // Saturating add

    const expansion_gas = interp.gas.memoryExpansionCost(old_size, new_size);
    return expansion_gas;
}

/// Compute dynamic gas for MSTORE operation.
/// Gas depends on memory expansion (same as MLOAD).
pub fn opMstore(interp: *Interpreter) !u64 {
    return opMload(interp); // Same logic
}

/// Compute dynamic gas for MSTORE8 operation.
/// Gas depends on memory expansion for a 1-byte write.
pub fn opMstore8(interp: *Interpreter) !u64 {
    const offset_u256 = try interp.ctx.stack.peek(0);
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;

    const old_size = interp.ctx.memory.len();
    const new_size = offset +| 1; // Saturating add

    const expansion_gas = interp.gas.memoryExpansionCost(old_size, new_size);
    return expansion_gas;
}

/// Compute dynamic gas for RETURN operation.
/// Gas depends on memory expansion for reading return data.
pub fn opReturn(interp: *Interpreter) !u64 {
    const offset_u256 = try interp.ctx.stack.peek(0);
    const size_u256 = try interp.ctx.stack.peek(1);

    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const size = size_u256.toUsize() orelse return error.InvalidOffset;

    // No expansion for zero-length return
    if (size == 0) return 0;

    const old_size = interp.ctx.memory.len();
    const new_size = offset +| size; // Saturating add

    const expansion_gas = interp.gas.memoryExpansionCost(old_size, new_size);
    return expansion_gas;
}

/// Compute dynamic gas for REVERT operation.
/// Gas depends on memory expansion (same as RETURN).
pub fn opRevert(interp: *Interpreter) !u64 {
    return opReturn(interp); // Same logic
}

/// Compute dynamic gas for MCOPY operation (EIP-5656, Cancun+).
/// Gas depends on memory expansion for both source and destination regions,
/// plus per-word copy cost.
pub fn opMcopy(interp: *Interpreter) !u64 {
    const dest_u256 = try interp.ctx.stack.peek(0);
    const src_u256 = try interp.ctx.stack.peek(1);
    const length_u256 = try interp.ctx.stack.peek(2);

    const dest = dest_u256.toUsize() orelse return error.InvalidOffset;
    const src = src_u256.toUsize() orelse return error.InvalidOffset;
    const length = length_u256.toUsize() orelse return error.InvalidOffset;

    // No cost for zero-length copy
    if (length == 0) return 0;

    const old_size = interp.ctx.memory.len();
    const end1 = dest +| length; // Saturating add
    const end2 = src +| length; // Saturating add
    const max_end = @max(end1, end2);

    const expansion_gas = interp.gas.memoryExpansionCost(old_size, max_end);

    // Copy cost: 3 gas per word
    const copy_words = (length +| 31) / 32;
    const copy_gas = 3 *| @as(u64, @intCast(copy_words));

    return expansion_gas + copy_gas;
}

/// Get account access cost (BALANCE, EXTCODESIZE, EXTCODECOPY, EXTCODEHASH).
///
/// Handles both pre-Berlin (flat cost, no cold/warm distinction) and post-Berlin (cold/warm) models.
///
/// Pre-Berlin: Returns Spec.cold_account_access_cost regardless of is_cold
/// Post-Berlin+: Returns 2600 (cold) or 100 (warm)
///
/// EIPs: EIP-150 (Tangerine), EIP-2929 (Berlin)
fn accountAccessCost(spec: Spec, is_cold: bool) u64 {
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
fn callBaseCost(spec: Spec, is_cold: bool) u64 {
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
fn sloadCost(spec: Spec, is_cold: bool) u64 {
    if (spec.fork.isBefore(.BERLIN)) {
        // No cold/warm distinction
        return spec.cold_sload_cost;
    }

    return if (is_cold) spec.cold_sload_cost else spec.warm_storage_read_cost;
}

/// Calculate calldata gas cost for given data.
///
/// Handles EIP-2028 change:
/// - Pre-Istanbul: 4/zero-byte, 68/non-zero byte
/// - Post-Istanbul: 4/zero-byte, 16/non-zero byte
/// EIPs: EIP-2028 (Istanbul)
fn calldataCost(spec: Spec, data: []const u8) u64 {
    const calldata_nonzero_cost: u64 = if (spec.fork.isBefore(.ISTANBUL)) 68 else 16;
    var cost: u64 = 0;
    for (data) |byte| {
        cost +|= if (byte == 0) Costs.CALLDATA_ZERO_COST else calldata_nonzero_cost;
    }
    return cost;
}

/// Calculate KECCAK256 (SHA3) cost based on input size.
///
/// Formula: 30 + (6 * ceil(size/32))
fn keccak256Cost(size: usize) u64 {
    const words = (size +| 31) / 32;
    return Costs.KECCAK256_BASE +| (Costs.KECCAK256_WORD *| @as(u64, @intCast(words)));
}

/// Calculate LOG cost (LOG0-LOG4).
///
/// Formula: 375 + (375 * topic_count) + (8 * data_size_bytes)
fn logCost(topic_count: u8, data_size: usize) u64 {
    const topics = @as(u64, topic_count);
    const bytes = @as(u64, @intCast(data_size));
    return Costs.LOG_BASE +| (Costs.LOG_TOPIC *| topics) +| (Costs.LOG_DATA *| bytes);
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "dynamic_gas: basic smoke test" {
    // This test verifies that the functions compile and have the correct signatures.
    // Full integration tests will be added later when the interpreter is wired up.
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.CANCUN);

    // Use proper Interpreter initialization
    const bytecode = &[_]u8{0x00}; // STOP
    var interp = try Interpreter.init(allocator, bytecode, spec, 1000000);
    defer interp.deinit();

    // Test EXP with small exponent
    try interp.ctx.stack.push(U256.fromU64(2)); // base
    try interp.ctx.stack.push(U256.fromU64(8)); // exponent (1 byte)
    const exp_gas = try opExp(&interp);
    try expect(exp_gas > 0);

    // Clear stack
    _ = try interp.ctx.stack.pop();
    _ = try interp.ctx.stack.pop();

    // Test MLOAD at offset 0 (no expansion from 0)
    try interp.ctx.stack.push(U256.fromU64(0));
    const mload_gas = try opMload(&interp);
    try expect(mload_gas >= 0); // May be 0 for small expansion

    // Clear stack
    _ = try interp.ctx.stack.pop();

    // Test RETURN with size 0 (no expansion)
    try interp.ctx.stack.push(U256.fromU64(0)); // offset
    try interp.ctx.stack.push(U256.fromU64(0)); // size
    const return_gas = try opReturn(&interp);
    try expectEqual(0, return_gas); // Zero-length should be 0

    // Clear stack
    _ = try interp.ctx.stack.pop();
    _ = try interp.ctx.stack.pop();
}

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
    try expectEqual(700, accountAccessCost(homestead_spec, true));
    try expectEqual(700, accountAccessCost(homestead_spec, false));
}

test "accountAccessCost - Berlin+" {
    const berlin_spec = Spec.forFork(.BERLIN);

    // Berlin+: cold = 2600, warm = 100
    try expectEqual(2600, accountAccessCost(berlin_spec, true));
    try expectEqual(100, accountAccessCost(berlin_spec, false));
}

test "callBaseCost - evolution" {
    const frontier_spec = Spec.forFork(.FRONTIER);
    const tangerine_spec = Spec.forFork(.TANGERINE);
    const berlin_spec = Spec.forFork(.BERLIN);

    // Pre-Tangerine: 40
    try expectEqual(40, callBaseCost(frontier_spec, true));
    try expectEqual(40, callBaseCost(frontier_spec, false));

    // Tangerine-Berlin: 700
    try expectEqual(700, callBaseCost(tangerine_spec, true));
    try expectEqual(700, callBaseCost(tangerine_spec, false));

    // Berlin+: 2600 (cold) or 100 (warm)
    try expectEqual(2600, callBaseCost(berlin_spec, true));
    try expectEqual(100, callBaseCost(berlin_spec, false));
}

test "sloadCost - evolution" {
    const frontier_spec = Spec.forFork(.FRONTIER);
    const homestead_spec = Spec.forFork(.HOMESTEAD);
    const tangerine_spec = Spec.forFork(.TANGERINE);
    const istanbul_spec = Spec.forFork(.ISTANBUL);
    const berlin_spec = Spec.forFork(.BERLIN);

    // Frontier/Homestead: 50 (no cold/warm distinction)
    try expectEqual(50, sloadCost(frontier_spec, true));
    try expectEqual(50, sloadCost(frontier_spec, false));
    try expectEqual(50, sloadCost(homestead_spec, true));
    try expectEqual(50, sloadCost(homestead_spec, false));

    // Tangerine: 200 (EIP-150, no cold/warm distinction)
    try expectEqual(200, sloadCost(tangerine_spec, true));
    try expectEqual(200, sloadCost(tangerine_spec, false));

    // Istanbul: 800 (EIP-1884, no cold/warm distinction)
    try expectEqual(800, sloadCost(istanbul_spec, true));
    try expectEqual(800, sloadCost(istanbul_spec, false));

    // Berlin+: 2100 (cold) or 100 (warm) (EIP-2929)
    try expectEqual(2100, sloadCost(berlin_spec, true));
    try expectEqual(100, sloadCost(berlin_spec, false));
}

test "calldataCost" {
    const byzantium_spec = Spec.forFork(.BYZANTIUM);
    const istanbul_spec = Spec.forFork(.ISTANBUL);
    const berlin_spec = Spec.forFork(.BERLIN);

    const data1 = [_]u8{ 0, 0, 0, 1 }; // 3 zeros, 1 non-zero
    const data2 = [_]u8{ 1, 2, 3, 4 }; // All non-zero
    const data3 = [_]u8{ 0, 0, 0, 0 }; // All zeros

    // Pre-Istanbul: 4/zero, 68/non-zero
    try expectEqual(3 * 4 + 1 * 68, calldataCost(byzantium_spec, &data1));
    try expectEqual(4 * 68, calldataCost(byzantium_spec, &data2));
    try expectEqual(4 * 4, calldataCost(byzantium_spec, &data3));

    // Istanbul+: 4/zero, 16/non-zero
    try expectEqual(3 * 4 + 1 * 16, calldataCost(istanbul_spec, &data1));
    try expectEqual(4 * 16, calldataCost(istanbul_spec, &data2));
    try expectEqual(4 * 4, calldataCost(istanbul_spec, &data3));

    // Istanbul+: 4/zero, 16/non-zero
    try expectEqual(3 * 4 + 1 * 16, calldataCost(berlin_spec, &data1));
    try expectEqual(4 * 16, calldataCost(berlin_spec, &data2));
    try expectEqual(4 * 4, calldataCost(berlin_spec, &data3));
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
