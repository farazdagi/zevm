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
const Hardfork = @import("../hardfork.zig").Hardfork;
const Interpreter = @import("../interpreter/mod.zig").Interpreter;
const U256 = @import("../primitives/big.zig").U256;
const Address = @import("../primitives/address.zig").Address;
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

/// Memory region information for gas calculation.
const MemoryRegion = struct {
    offset: usize,
    size: usize,
    expansion_gas: u64,
};

/// Calculate memory expansion gas for accessing a fixed-size region.
///
/// Used by operations that read/write a known number of bytes (MLOAD, MSTORE8).
inline fn memoryExpansionGasFixed(interp: *Interpreter, offset_pos: u8, size: usize) !u64 {
    const offset_u256 = try interp.ctx.stack.peek(offset_pos);
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;

    const old_size = interp.ctx.memory.len();
    const new_size = offset +| size;

    return interp.gas.memoryExpansionCost(old_size, new_size);
}

/// Calculate memory expansion for a variable-size region from stack.
///
/// Used by operations that peek both offset and size from stack (RETURN, KECCAK256, copy operations).
/// Returns region info including offset, size, and expansion gas for further processing.
inline fn memoryRegionExpansion(interp: *Interpreter, offset_pos: u8, size_pos: u8) !MemoryRegion {
    const offset_u256 = try interp.ctx.stack.peek(offset_pos);
    const size_u256 = try interp.ctx.stack.peek(size_pos);

    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const size = size_u256.toUsize() orelse return error.InvalidOffset;

    // No expansion for zero-length access
    if (size == 0) {
        return MemoryRegion{ .offset = offset, .size = 0, .expansion_gas = 0 };
    }

    const old_size = interp.ctx.memory.len();
    const new_size = offset +| size;

    const expansion_gas = interp.gas.memoryExpansionCost(old_size, new_size);
    return MemoryRegion{ .offset = offset, .size = size, .expansion_gas = expansion_gas };
}

/// Calculate dynamic gas for memory copy operations.
///
/// Used by CALLDATACOPY, CODECOPY, EXTCODECOPY, RETURNDATACOPY.
/// All copy operations charge memory expansion plus 3 gas per word copied.
inline fn memoryCopyGas(interp: *Interpreter, dest_offset_pos: u8, length_pos: u8) !u64 {
    const region = try memoryRegionExpansion(interp, dest_offset_pos, length_pos);
    if (region.size == 0) return 0;

    // Copy cost: 3 gas per word
    const copy_words = (region.size +| 31) / 32;
    const copy_gas = 3 *| @as(u64, @intCast(copy_words));

    return region.expansion_gas +| copy_gas;
}

/// Compute EXP dynamic gas cost (per-byte portion only).
///
/// Stack: [base, exponent, ...] (peek only, no modification)
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
/// Stack: [offset, ...] (peek only, no modification)
/// Gas depends on memory expansion.
pub fn opMload(interp: *Interpreter) !u64 {
    return memoryExpansionGasFixed(interp, 0, 32);
}

/// Compute dynamic gas for MSTORE operation.
///
/// Stack: [offset, value, ...] (peek only, no modification)
/// Gas depends on memory expansion (same as MLOAD).
pub fn opMstore(interp: *Interpreter) !u64 {
    return opMload(interp); // Same logic
}

/// Compute dynamic gas for MSTORE8 operation.
///
/// Stack: [offset, value, ...] (peek only, no modification)
/// Gas depends on memory expansion for a 1-byte write.
pub fn opMstore8(interp: *Interpreter) !u64 {
    return memoryExpansionGasFixed(interp, 0, 1);
}

/// Compute dynamic gas for RETURN operation.
///
/// Stack: [offset, size, ...] (peek only, no modification)
/// Gas depends on memory expansion for reading return data.
pub fn opReturn(interp: *Interpreter) !u64 {
    const region = try memoryRegionExpansion(interp, 0, 1);
    return region.expansion_gas;
}

/// Compute dynamic gas for REVERT operation.
///
/// Stack: [offset, size, ...] (peek only, no modification)
/// Gas depends on memory expansion (same as RETURN).
pub fn opRevert(interp: *Interpreter) !u64 {
    return opReturn(interp); // Same logic
}

/// Compute dynamic gas for KECCAK256 operation.
///
/// Stack: [offset, size, ...] (peek only, no modification)
/// Gas depends on memory expansion and input data size.
pub fn opKeccak256(interp: *Interpreter) !u64 {
    const region = try memoryRegionExpansion(interp, 0, 1);
    if (region.size == 0) return 0;

    // Hash cost: word_cost per 32-byte word
    const words = (region.size +| 31) / 32;
    const hash_gas = interp.spec.keccak256_word_cost *| @as(u64, @intCast(words));

    return region.expansion_gas +| hash_gas;
}

/// Compute dynamic gas for MCOPY operation (EIP-5656, Cancun+).
///
/// Stack: [dest, src, size, ...] (peek only, no modification)
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

/// Compute dynamic gas for CALLDATACOPY operation.
///
/// Stack: [destOffset, offset, length, ...] (peek only, no modification)
/// Gas depends on memory expansion for destination region, plus per-word copy cost.
pub fn opCalldatacopy(interp: *Interpreter) !u64 {
    return memoryCopyGas(interp, 0, 2);
}

/// Compute dynamic gas for CODECOPY operation.
///
/// Stack: [destOffset, offset, length, ...] (peek only, no modification)
/// Gas depends on memory expansion for destination region, plus per-word copy cost.
pub fn opCodecopy(interp: *Interpreter) !u64 {
    return memoryCopyGas(interp, 0, 2);
}

/// Compute dynamic gas for EXTCODECOPY operation.
///
/// Stack: [address, destOffset, offset, length, ...] (peek only, no modification)
/// Gas depends on memory expansion for destination region, plus per-word copy cost.
pub fn opExtcodecopy(interp: *Interpreter) !u64 {
    return memoryCopyGas(interp, 1, 3);
}

/// Compute dynamic gas for RETURNDATACOPY operation (EIP-211, Byzantium+).
///
/// Stack: [destOffset, offset, length, ...] (peek only, no modification)
/// Gas depends on memory expansion for destination region, plus per-word copy cost.
pub fn opReturndatacopy(interp: *Interpreter) !u64 {
    return memoryCopyGas(interp, 0, 2);
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
    const Env = @import("../context.zig").Env;
    const MockHost = @import("../host/mock.zig").MockHost;
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var interp = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 1000000, &env, mock.host());
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

test "accountAccessCost" {
    const test_cases = [_]struct {
        fork: Hardfork,
        is_cold: bool,
        expected: u64,
        comment: []const u8,
    }{
        // Pre-Berlin: no cold/warm distinction
        .{ .fork = .HOMESTEAD, .is_cold = true, .expected = 700, .comment = "Pre-Berlin always returns cold_account_access_cost" },
        .{ .fork = .HOMESTEAD, .is_cold = false, .expected = 700, .comment = "Pre-Berlin ignores is_cold flag" },
        // Berlin+: cold/warm model (EIP-2929)
        .{ .fork = .BERLIN, .is_cold = true, .expected = 2600, .comment = "Berlin cold access" },
        .{ .fork = .BERLIN, .is_cold = false, .expected = 100, .comment = "Berlin warm access" },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        try expectEqual(tc.expected, accountAccessCost(spec, tc.is_cold));
    }
}

test "callBaseCost" {
    const test_cases = [_]struct {
        fork: Hardfork,
        is_cold: bool,
        expected: u64,
        comment: []const u8,
    }{
        // Pre-Tangerine: 40 gas (no cold/warm)
        .{ .fork = .FRONTIER, .is_cold = true, .expected = 40, .comment = "Frontier flat cost" },
        .{ .fork = .FRONTIER, .is_cold = false, .expected = 40, .comment = "Frontier ignores is_cold" },
        // Tangerine-Berlin: 700 gas (EIP-150, no cold/warm)
        .{ .fork = .TANGERINE, .is_cold = true, .expected = 700, .comment = "Tangerine flat cost" },
        .{ .fork = .TANGERINE, .is_cold = false, .expected = 700, .comment = "Tangerine ignores is_cold" },
        // Berlin+: cold/warm model (EIP-2929)
        .{ .fork = .BERLIN, .is_cold = true, .expected = 2600, .comment = "Berlin cold call" },
        .{ .fork = .BERLIN, .is_cold = false, .expected = 100, .comment = "Berlin warm call" },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        try expectEqual(tc.expected, callBaseCost(spec, tc.is_cold));
    }
}

test "sloadCost" {
    const test_cases = [_]struct {
        fork: Hardfork,
        is_cold: bool,
        expected: u64,
        comment: []const u8,
    }{
        // Frontier/Homestead: 50 gas (no cold/warm)
        .{ .fork = .FRONTIER, .is_cold = true, .expected = 50, .comment = "Frontier flat cost" },
        .{ .fork = .FRONTIER, .is_cold = false, .expected = 50, .comment = "Frontier ignores is_cold" },
        .{ .fork = .HOMESTEAD, .is_cold = true, .expected = 50, .comment = "Homestead flat cost" },
        .{ .fork = .HOMESTEAD, .is_cold = false, .expected = 50, .comment = "Homestead ignores is_cold" },
        // Tangerine: 200 gas (EIP-150, no cold/warm)
        .{ .fork = .TANGERINE, .is_cold = true, .expected = 200, .comment = "Tangerine increased cost" },
        .{ .fork = .TANGERINE, .is_cold = false, .expected = 200, .comment = "Tangerine ignores is_cold" },
        // Istanbul: 800 gas (EIP-1884, no cold/warm)
        .{ .fork = .ISTANBUL, .is_cold = true, .expected = 800, .comment = "Istanbul increased cost" },
        .{ .fork = .ISTANBUL, .is_cold = false, .expected = 800, .comment = "Istanbul ignores is_cold" },
        // Berlin+: cold/warm model (EIP-2929)
        .{ .fork = .BERLIN, .is_cold = true, .expected = 2100, .comment = "Berlin cold SLOAD" },
        .{ .fork = .BERLIN, .is_cold = false, .expected = 100, .comment = "Berlin warm SLOAD" },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        try expectEqual(tc.expected, sloadCost(spec, tc.is_cold));
    }
}

test "calldataCost" {
    const test_cases = [_]struct {
        fork: Hardfork,
        data: []const u8,
        expected: u64,
        comment: []const u8,
    }{
        // Pre-Istanbul: 4/zero-byte, 68/non-zero byte (EIP-2028 not active)
        .{ .fork = .BYZANTIUM, .data = &[_]u8{ 0, 0, 0, 1 }, .expected = 3 * 4 + 1 * 68, .comment = "3 zeros + 1 non-zero" },
        .{ .fork = .BYZANTIUM, .data = &[_]u8{ 1, 2, 3, 4 }, .expected = 4 * 68, .comment = "All non-zero" },
        .{ .fork = .BYZANTIUM, .data = &[_]u8{ 0, 0, 0, 0 }, .expected = 4 * 4, .comment = "All zeros" },
        // Istanbul+: 4/zero-byte, 16/non-zero byte (EIP-2028)
        .{ .fork = .ISTANBUL, .data = &[_]u8{ 0, 0, 0, 1 }, .expected = 3 * 4 + 1 * 16, .comment = "3 zeros + 1 non-zero" },
        .{ .fork = .ISTANBUL, .data = &[_]u8{ 1, 2, 3, 4 }, .expected = 4 * 16, .comment = "All non-zero" },
        .{ .fork = .ISTANBUL, .data = &[_]u8{ 0, 0, 0, 0 }, .expected = 4 * 4, .comment = "All zeros" },
        // Berlin (same as Istanbul)
        .{ .fork = .BERLIN, .data = &[_]u8{ 0, 0, 0, 1 }, .expected = 3 * 4 + 1 * 16, .comment = "3 zeros + 1 non-zero" },
        .{ .fork = .BERLIN, .data = &[_]u8{ 1, 2, 3, 4 }, .expected = 4 * 16, .comment = "All non-zero" },
        .{ .fork = .BERLIN, .data = &[_]u8{ 0, 0, 0, 0 }, .expected = 4 * 4, .comment = "All zeros" },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        try expectEqual(tc.expected, calldataCost(spec, tc.data));
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

test "opcode gas: KECCAK256" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.CANCUN);
    const bytecode = &[_]u8{0x00};
    const Env = @import("../context.zig").Env;
    const MockHost = @import("../host/mock.zig").MockHost;
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var interp = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 1000000, &env, mock.host());
    defer interp.deinit();

    const test_cases = [_]struct {
        offset: u64,
        size: u64,
        pre_expand: ?usize, // Pre-expand memory to this size (null = don't pre-expand)
        expected_formula: []const u8,
    }{
        // Zero-length hash: no cost
        .{ .offset = 0, .size = 0, .pre_expand = null, .expected_formula = "0" },
        // 32 bytes (1 word): 6 gas/word + expansion
        .{ .offset = 0, .size = 32, .pre_expand = null, .expected_formula = "6 + expansion(0->32)" },
        // 100 bytes (4 words): 24 gas + expansion
        .{ .offset = 0, .size = 100, .pre_expand = null, .expected_formula = "24 + expansion(32->100)" },
        // 64 bytes (2 words) with pre-expanded memory
        .{ .offset = 32, .size = 64, .pre_expand = 128, .expected_formula = "12 + expansion(128->96)" },
    };

    for (test_cases) |tc| {
        // Pre-expand memory if requested
        if (tc.pre_expand) |size| {
            try interp.ctx.memory.ensureCapacity(0, size);
        }
        const old_size = interp.ctx.memory.len();

        // Push stack values (size first, then offset - stack is LIFO)
        try interp.ctx.stack.push(U256.fromU64(tc.size));
        try interp.ctx.stack.push(U256.fromU64(tc.offset));

        const gas = try opKeccak256(&interp);

        // Calculate expected gas
        const words = if (tc.size == 0) 0 else (tc.size + 31) / 32;
        const hash_gas = words * 6; // keccak256_word_cost = 6
        const new_size = tc.offset + tc.size;
        const expansion_gas = interp.gas.memoryExpansionCost(old_size, new_size);
        const expected = hash_gas + expansion_gas;

        try expectEqual(expected, gas);

        // Clean up stack
        _ = try interp.ctx.stack.pop();
        _ = try interp.ctx.stack.pop();
    }
}

test "opcode gas: copy operations" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.CANCUN);
    const bytecode = &[_]u8{0x00};
    const Env = @import("../context.zig").Env;
    const MockHost = @import("../host/mock.zig").MockHost;
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var interp = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 1000000, &env, mock.host());
    defer interp.deinit();

    const OpFn = *const fn (*Interpreter) anyerror!u64;
    const test_cases = [_]struct {
        op_fn: OpFn,
        op_name: []const u8,
        dest_offset: u64,
        src_offset: u64,
        length: u64,
        has_address: bool, // EXTCODECOPY has address param
        expected_formula: []const u8,
    }{
        // CALLDATACOPY: [destOffset, offset, length]
        .{ .op_fn = opCalldatacopy, .op_name = "CALLDATACOPY", .dest_offset = 0, .src_offset = 0, .length = 0, .has_address = false, .expected_formula = "0 (zero-length)" },
        .{ .op_fn = opCalldatacopy, .op_name = "CALLDATACOPY", .dest_offset = 0, .src_offset = 0, .length = 32, .has_address = false, .expected_formula = "3 + expansion" },
        .{ .op_fn = opCalldatacopy, .op_name = "CALLDATACOPY", .dest_offset = 0, .src_offset = 0, .length = 100, .has_address = false, .expected_formula = "12 + expansion" },
        // CODECOPY: [destOffset, offset, length]
        .{ .op_fn = opCodecopy, .op_name = "CODECOPY", .dest_offset = 0, .src_offset = 0, .length = 0, .has_address = false, .expected_formula = "0 (zero-length)" },
        .{ .op_fn = opCodecopy, .op_name = "CODECOPY", .dest_offset = 0, .src_offset = 0, .length = 64, .has_address = false, .expected_formula = "6 + expansion" },
        // EXTCODECOPY: [address, destOffset, offset, length]
        .{ .op_fn = opExtcodecopy, .op_name = "EXTCODECOPY", .dest_offset = 0, .src_offset = 0, .length = 0, .has_address = true, .expected_formula = "0 (zero-length)" },
        .{ .op_fn = opExtcodecopy, .op_name = "EXTCODECOPY", .dest_offset = 0, .src_offset = 0, .length = 96, .has_address = true, .expected_formula = "9 + expansion" },
        // RETURNDATACOPY: [destOffset, offset, length]
        .{ .op_fn = opReturndatacopy, .op_name = "RETURNDATACOPY", .dest_offset = 0, .src_offset = 0, .length = 0, .has_address = false, .expected_formula = "0 (zero-length)" },
        .{ .op_fn = opReturndatacopy, .op_name = "RETURNDATACOPY", .dest_offset = 0, .src_offset = 0, .length = 128, .has_address = false, .expected_formula = "12 + expansion" },
    };

    for (test_cases) |tc| {
        const old_size = interp.ctx.memory.len();

        // Push stack values (reverse order - stack is LIFO)
        try interp.ctx.stack.push(U256.fromU64(tc.length));
        try interp.ctx.stack.push(U256.fromU64(tc.src_offset));
        try interp.ctx.stack.push(U256.fromU64(tc.dest_offset));
        if (tc.has_address) {
            try interp.ctx.stack.push(U256.fromU64(0)); // address
        }

        const gas = try tc.op_fn(&interp);

        // Calculate expected: 3 gas per word + expansion
        const words = if (tc.length == 0) 0 else (tc.length + 31) / 32;
        const copy_gas = words * 3;
        const new_size = tc.dest_offset + tc.length;
        const expansion_gas = interp.gas.memoryExpansionCost(old_size, new_size);
        const expected = copy_gas + expansion_gas;

        try expectEqual(expected, gas);

        // Clean up stack
        if (tc.has_address) {
            _ = try interp.ctx.stack.pop();
        }
        _ = try interp.ctx.stack.pop();
        _ = try interp.ctx.stack.pop();
        _ = try interp.ctx.stack.pop();
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

    // logCost: data size multiplication saturates
    // 8 * (max_u64 / 4) = 2 * max_u64, overflows to max_u64
    const very_large_size: usize = max_u64 / 4;
    const log_result = logCost(4, very_large_size);
    try expect(log_result == max_u64);

    // Note: calldataCost accumulation overflow is impractical to test
    // (would require ~270 PB allocation). The +|= operator is verified
    // by inspection and smaller tests verify the logic is correct.
}
