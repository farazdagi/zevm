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
const CallContext = @import("../interpreter/interpreter.zig").CallContext;
const AnalyzedBytecode = @import("../interpreter/bytecode.zig").AnalyzedBytecode;
const U256 = @import("../primitives/big.zig").U256;
const Address = @import("../primitives/address.zig").Address;
const FixedGasCosts = @import("FixedGasCosts.zig");
const AccessList = @import("../AccessList.zig");

/// Calculate total memory cost for given byte size.
///
/// Quadratic cost: words^2 / 512 + 3 * words
pub inline fn memoryCost(byte_size: usize) u64 {
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
/// All copy operations charge memory expansion plus `copy_word_cost` gas per word copied.
inline fn memoryCopyGas(interp: *Interpreter, dest_offset_pos: u8, length_pos: u8) !u64 {
    const region = try memoryRegionExpansion(interp, dest_offset_pos, length_pos);
    if (region.size == 0) return 0;

    // Copy cost: copy_word_cost gas per word
    const copy_words = (region.size +| 31) / 32;
    const copy_gas = interp.spec.copy_word_cost *| @as(u64, @intCast(copy_words));

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

    // Copy cost: copy_word_cost gas per word
    const copy_words = (length +| 31) / 32;
    const copy_gas = interp.spec.copy_word_cost *| @as(u64, @intCast(copy_words));

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

/// Compute dynamic gas for EXTCODECOPY operation (EIP-2929).
///
/// Stack: [address, destOffset, offset, length, ...]
/// Gas depends on:
/// - Account access cost (cold/warm)
/// - Memory expansion for destination region
/// - Per-word copy cost
pub fn opExtcodecopy(interp: *Interpreter) !u64 {
    // Account access cost (EIP-2929).
    const address = Address.fromU256(try interp.ctx.stack.peek(0));
    const is_cold = interp.access_list.warmAddress(address);
    var total: u64 = accountAccessCost(interp.spec, is_cold);

    // Memory expansion and copy costs.
    total +|= try memoryCopyGas(interp, 1, 3);

    return total;
}

/// Compute dynamic gas for RETURNDATACOPY operation (EIP-211, Byzantium+).
///
/// Stack: [destOffset, offset, length, ...] (peek only, no modification)
/// Gas depends on memory expansion for destination region, plus per-word copy cost.
pub fn opReturndatacopy(interp: *Interpreter) !u64 {
    return memoryCopyGas(interp, 0, 2);
}

/// Get account access cost for cold/warm access (EIP-2929).
///
/// Returns the *additional* dynamic gas cost beyond the base opcode cost.
///
/// Pre-Berlin: 0 (no dynamic gas, all costs are static)
/// Berlin+ cold: 2500 (cold_account_access_cost - warm_storage_read_cost)
/// Berlin+ warm: 0 (no additional cost, base already covers warm access)
///
/// Used by: BALANCE, EXTCODESIZE, EXTCODECOPY, EXTCODEHASH,
///          CALL, CALLCODE, DELEGATECALL, STATICCALL
///
/// EIPs: EIP-150 (Tangerine), EIP-2929 (Berlin)
inline fn accountAccessCost(spec: Spec, is_cold: bool) u64 {
    // Warm access or pre-Berlin: no dynamic gas, all costs are in base opcode cost.
    if (!is_cold or spec.fork.isBefore(.BERLIN)) {
        return 0;
    }

    // Cold: extra cost beyond warm base.
    // Subtracting because we need additional dynamic gas (so, subtracting the base cost).
    // In spec we have a base access cost equal to the warm access cost (100 gas for Berlin+).
    return spec.cold_account_access_cost - spec.warm_storage_read_cost;
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
inline fn sloadCost(spec: Spec, is_cold: bool) u64 {
    if (spec.fork.isBefore(.BERLIN)) {
        // No cold/warm distinction
        return spec.cold_sload_cost;
    }

    return if (is_cold) spec.cold_sload_cost else spec.warm_storage_read_cost;
}

/// Compute dynamic gas for BALANCE operation (EIP-2929).
///
/// Stack: [address, ...]
pub fn opBalance(interp: *Interpreter) !u64 {
    const address = Address.fromU256(try interp.ctx.stack.peek(0));
    const is_cold = interp.access_list.warmAddress(address);
    return accountAccessCost(interp.spec, is_cold);
}

/// Compute dynamic gas for EXTCODESIZE operation (EIP-2929).
///
/// Stack: [address, ...]
pub fn opExtcodesize(interp: *Interpreter) !u64 {
    const address = Address.fromU256(try interp.ctx.stack.peek(0));
    const is_cold = interp.access_list.warmAddress(address);
    return accountAccessCost(interp.spec, is_cold);
}

/// Compute dynamic gas for EXTCODEHASH operation (EIP-2929).
///
/// Stack: [address, ...]
pub fn opExtcodehash(interp: *Interpreter) !u64 {
    const address = Address.fromU256(try interp.ctx.stack.peek(0));
    const is_cold = interp.access_list.warmAddress(address);
    return accountAccessCost(interp.spec, is_cold);
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
        cost +|= if (byte == 0) spec.calldata_zero_cost else calldata_nonzero_cost;
    }
    return cost;
}

/// Calculate LOG cost (LOG0-LOG4).
///
/// Formula: log_base_cost + (log_topic_cost * topic_count) + (log_data_cost * data_size_bytes)
inline fn logCost(spec: Spec, topic_count: u8, data_size: usize) u64 {
    const topics = @as(u64, topic_count);
    const bytes = @as(u64, @intCast(data_size));
    return spec.log_base_cost +| (spec.log_topic_cost *| topics) +| (spec.log_data_cost *| bytes);
}

/// Calculate memory expansion gas for call operations.
///
/// Used by: CALL, CALLCODE, DELEGATECALL, STATICCALL.
/// Computes the cost of expanding memory to accommodate both input args and return data regions.
inline fn callMemoryExpansion(
    interp: *Interpreter,
    args_offset: usize,
    args_size: usize,
    ret_offset: usize,
    ret_size: usize,
) u64 {
    const old_size = interp.ctx.memory.len();
    const args_end = if (args_size > 0) args_offset +| args_size else 0;
    const ret_end = if (ret_size > 0) ret_offset +| ret_size else 0;
    const new_size = @max(args_end, ret_end);

    return if (new_size > old_size)
        interp.gas.memoryExpansionCost(old_size, new_size)
    else
        0;
}

/// Compute dynamic gas for CALL operation.
///
/// Stack: [gas, address, value, argsOffset, argsSize, retOffset, retSize, ...]
/// Gas depends on:
/// - Base access cost (cold/warm account)
/// - Memory expansion (for max of input and output regions)
/// - Value transfer cost (if value > 0)
/// - New account creation cost (if sending value to non-existent account)
///
/// EIPs: EIP-150, EIP-2929
pub fn opCall(interp: *Interpreter) !u64 {
    // Peek stack values (positions from top of stack).
    const address_u256 = try interp.ctx.stack.peek(1);
    const value_u256 = try interp.ctx.stack.peek(2);
    const args_offset_u256 = try interp.ctx.stack.peek(3);
    const args_size_u256 = try interp.ctx.stack.peek(4);
    const ret_offset_u256 = try interp.ctx.stack.peek(5);
    const ret_size_u256 = try interp.ctx.stack.peek(6);

    // Convert address U256 to Address (take last 20 bytes).
    const target = Address.fromU256(address_u256);

    // Check if value transfer.
    const has_value = !value_u256.isZero();

    // Convert offsets and lengths to usize.
    const args_offset = args_offset_u256.toUsize() orelse return error.InvalidOffset;
    const args_size = args_size_u256.toUsize() orelse return error.InvalidOffset;
    const ret_offset = ret_offset_u256.toUsize() orelse return error.InvalidOffset;
    const ret_size = ret_size_u256.toUsize() orelse return error.InvalidOffset;

    var total_gas: u64 = 0;

    // 1. Access cost (cold/warm).
    // EIP-2929: Warm the address and get whether it was cold.
    const is_cold = interp.access_list.warmAddress(target);
    total_gas +|= accountAccessCost(interp.spec, is_cold);

    // 2. Memory expansion cost.
    total_gas +|= callMemoryExpansion(interp, args_offset, args_size, ret_offset, ret_size);

    // 3. Value transfer cost.
    if (has_value) {
        total_gas +|= interp.spec.call_value_transfer_cost;

        // 4. New account creation cost (if sending value to non-existent account).
        if (!interp.host.accountExists(target)) {
            total_gas +|= interp.spec.call_new_account_cost;
        }
    }

    return total_gas;
}

/// Compute dynamic gas for CALLCODE operation.
///
/// Similar to CALL but executes code in caller's context.
/// Stack: [gas, address, value, argsOffset, argsSize, retOffset, retSize, ...]
pub fn opCallcode(interp: *Interpreter) !u64 {
    // Peek stack values (positions from top of stack).
    const address_u256 = try interp.ctx.stack.peek(1);
    const value_u256 = try interp.ctx.stack.peek(2);
    const args_offset_u256 = try interp.ctx.stack.peek(3);
    const args_size_u256 = try interp.ctx.stack.peek(4);
    const ret_offset_u256 = try interp.ctx.stack.peek(5);
    const ret_size_u256 = try interp.ctx.stack.peek(6);

    // Convert address U256 to Address (take last 20 bytes).
    const target = Address.fromU256(address_u256);

    // Check if value transfer.
    const has_value = !value_u256.isZero();

    // Convert offsets and lengths to usize.
    const args_offset = args_offset_u256.toUsize() orelse return error.InvalidOffset;
    const args_size = args_size_u256.toUsize() orelse return error.InvalidOffset;
    const ret_offset = ret_offset_u256.toUsize() orelse return error.InvalidOffset;
    const ret_size = ret_size_u256.toUsize() orelse return error.InvalidOffset;

    var total_gas: u64 = 0;

    // 1. Access cost (cold/warm).
    const is_cold = interp.access_list.warmAddress(target);
    total_gas +|= accountAccessCost(interp.spec, is_cold);

    // 2. Memory expansion cost.
    total_gas +|= callMemoryExpansion(interp, args_offset, args_size, ret_offset, ret_size);

    // 3. Value transfer cost.
    // CALLCODE doesn't create new accounts, but does charge for value transfer.
    if (has_value) {
        total_gas +|= interp.spec.call_value_transfer_cost;
    }

    return total_gas;
}

/// Compute dynamic gas for DELEGATECALL operation.
///
/// Similar to CALL but preserves caller and value from parent frame.
/// Stack: [gas, address, argsOffset, argsSize, retOffset, retSize, ...]
/// Note: No value parameter (6 args instead of 7).
pub fn opDelegatecall(interp: *Interpreter) !u64 {
    // Peek stack values (positions from top of stack).
    const address_u256 = try interp.ctx.stack.peek(1);
    const args_offset_u256 = try interp.ctx.stack.peek(2);
    const args_size_u256 = try interp.ctx.stack.peek(3);
    const ret_offset_u256 = try interp.ctx.stack.peek(4);
    const ret_size_u256 = try interp.ctx.stack.peek(5);

    // Convert address U256 to Address (take last 20 bytes).
    const target = Address.fromU256(address_u256);

    // Convert offsets and lengths to usize.
    const args_offset = args_offset_u256.toUsize() orelse return error.InvalidOffset;
    const args_size = args_size_u256.toUsize() orelse return error.InvalidOffset;
    const ret_offset = ret_offset_u256.toUsize() orelse return error.InvalidOffset;
    const ret_size = ret_size_u256.toUsize() orelse return error.InvalidOffset;

    var total_gas: u64 = 0;

    // 1. Access cost (cold/warm).
    const is_cold = interp.access_list.warmAddress(target);
    total_gas +|= accountAccessCost(interp.spec, is_cold);

    // 2. Memory expansion cost.
    total_gas +|= callMemoryExpansion(interp, args_offset, args_size, ret_offset, ret_size);

    // DELEGATECALL has no value transfer, so no additional costs.

    return total_gas;
}

/// Compute dynamic gas for STATICCALL operation.
///
/// Similar to CALL but disallows state modifications.
/// Stack: [gas, address, argsOffset, argsSize, retOffset, retSize, ...]
/// Note: No value parameter (6 args instead of 7).
pub fn opStaticcall(interp: *Interpreter) !u64 {
    // Peek stack values (positions from top of stack).
    const address_u256 = try interp.ctx.stack.peek(1);
    const args_offset_u256 = try interp.ctx.stack.peek(2);
    const args_size_u256 = try interp.ctx.stack.peek(3);
    const ret_offset_u256 = try interp.ctx.stack.peek(4);
    const ret_size_u256 = try interp.ctx.stack.peek(5);

    // Convert address U256 to Address (take last 20 bytes).
    const target = Address.fromU256(address_u256);

    // Convert offsets and lengths to usize.
    const args_offset = args_offset_u256.toUsize() orelse return error.InvalidOffset;
    const args_size = args_size_u256.toUsize() orelse return error.InvalidOffset;
    const ret_offset = ret_offset_u256.toUsize() orelse return error.InvalidOffset;
    const ret_size = ret_size_u256.toUsize() orelse return error.InvalidOffset;

    var total_gas: u64 = 0;

    // 1. Base access cost (cold/warm).
    const is_cold = interp.access_list.warmAddress(target);
    total_gas +|= accountAccessCost(interp.spec, is_cold);

    // 2. Memory expansion cost.
    total_gas +|= callMemoryExpansion(interp, args_offset, args_size, ret_offset, ret_size);

    // STATICCALL has no value transfer, so no additional costs.

    return total_gas;
}

/// Compute dynamic gas for SLOAD operation (EIP-2929).
///
/// Stack: [key, ...]
/// Gas depends on warm/cold status of the storage slot.
///
/// Pre-Berlin: Fixed cost (handled in base gas)
/// Berlin+: 2100 (cold) or 100 (warm)
pub fn opSload(interp: *Interpreter) !u64 {
    const key = try interp.ctx.stack.peek(0);
    const address = interp.ctx.contract.address;

    // Warm the slot and get whether it was cold.
    const is_cold = interp.access_list.warmSlot(address, key);

    if (is_cold or interp.spec.fork.isBefore(.BERLIN)) {
        return interp.spec.cold_sload_cost;
    }
    return interp.spec.warm_storage_read_cost;
}

/// Compute dynamic gas for SSTORE operation.
///
/// Gas cost depends on original, current, and new storage values.
/// Implements EIP-2200 (Istanbul) and EIP-2929 (Berlin) gas metering.
///
/// TODO: Implement when SSTORE opcode is fully implemented.
pub fn opSstore(interp: *Interpreter) !u64 {
    _ = interp;
    @panic("opSstore dynamic gas not implemented");
}

/// Generate LOG handler for given topic count.
///
/// All LOG operations have identical logic except for the number of topics.
/// This comptime function generates the handler at compile time.
///
/// For log0:
/// Stack: [offset, size, ...]
/// Formula: memory_expansion + log_base_cost + log_data_cost * data_size
///
/// For log4:
/// Stack: [offset, size, topic1, topic2, topic3, topic4, ...]
/// Formula: memory_expansion + log_base_cost + 4*log_topic_cost + log_data_cost * data_size
inline fn makeLogHandler(comptime topic_count: u8) fn (*Interpreter) anyerror!u64 {
    return struct {
        fn handler(interp: *Interpreter) !u64 {
            const region = try memoryRegionExpansion(interp, 0, 1);
            return region.expansion_gas +| logCost(interp.spec, topic_count, region.size);
        }
    }.handler;
}

/// Compute dynamic gas for LOG0 operation.
pub const opLog0 = makeLogHandler(0);

/// Compute dynamic gas for LOG1 operation.
pub const opLog1 = makeLogHandler(1);

/// Compute dynamic gas for LOG2 operation.
pub const opLog2 = makeLogHandler(2);

/// Compute dynamic gas for LOG3 operation.
pub const opLog3 = makeLogHandler(3);

/// Compute dynamic gas for LOG4 operation.
pub const opLog4 = makeLogHandler(4);

/// Compute dynamic gas for CREATE operation.
///
/// Gas cost includes memory expansion and init code metering (EIP-3860).
///
/// TODO: Implement when CREATE opcode is fully implemented.
pub fn opCreate(interp: *Interpreter) !u64 {
    _ = interp;
    @panic("opCreate dynamic gas not implemented");
}

/// Compute dynamic gas for CREATE2 operation.
///
/// Gas cost includes memory expansion, init code metering (EIP-3860),
/// and hash cost for address derivation.
///
/// TODO: Implement when CREATE2 opcode is fully implemented.
pub fn opCreate2(interp: *Interpreter) !u64 {
    _ = interp;
    @panic("opCreate2 dynamic gas not implemented");
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const CallExecutor = @import("../call_types.zig").CallExecutor;

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
        // Pre-Berlin: no dynamic gas (returns 0).
        .{ .fork = .HOMESTEAD, .is_cold = true, .expected = 0, .comment = "Pre-Berlin returns 0 (no dynamic gas)" },
        .{ .fork = .HOMESTEAD, .is_cold = false, .expected = 0, .comment = "Pre-Berlin ignores is_cold flag" },
        // Berlin+: cold/warm model (EIP-2929) - returns EXTRA cost beyond warm base.
        .{ .fork = .BERLIN, .is_cold = true, .expected = 2500, .comment = "Berlin cold access (2600-100)" },
        .{ .fork = .BERLIN, .is_cold = false, .expected = 0, .comment = "Berlin warm access (no extra cost)" },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        try expectEqual(tc.expected, accountAccessCost(spec, tc.is_cold));
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
    const spec = Spec.forFork(.CANCUN);

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
        try expectEqual(tc.expected, logCost(spec, tc.topic_count, tc.data_size));
    }
}

test "EIP-2929: account access opcodes - cold/warm costs" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);
    const bytecode = &[_]u8{0x00};
    const Env = @import("../context.zig").Env;
    const MockHost = @import("../host/mock.zig").MockHost;
    const env = Env.default();

    const GasCostFn = *const fn (*Interpreter) anyerror!u64;

    const test_cases = [_]GasCostFn{
        opBalance,
        opExtcodesize,
        opExtcodehash,
    };

    for (test_cases) |op_fn| {
        var mock = MockHost.init(allocator);
        defer mock.deinit();

        const analyzed = try AnalyzedBytecode.initUncached(allocator, try allocator.dupe(u8, bytecode));
        const ctx = try CallContext.init(allocator, analyzed, Address.zero(), Address.zero(), U256.ZERO);
        var return_data: []const u8 = &[_]u8{};

        // Use a real AccessList to test actual warming behavior.
        var access_list = AccessList.init(allocator);
        defer access_list.deinit();

        var interp = Interpreter.init(allocator, ctx, .{
            .spec = spec,
            .gas_limit = 1000000,
            .env = &env,
            .host = mock.host(),
            .return_data_buffer = &return_data,
            .is_static = false,
            .call_executor = CallExecutor.noOp(),
            .access_list = access_list.accessor(),
        });
        defer interp.deinit();

        const test_addr = U256.fromU64(0x42424242);

        // First call - cold access (returns 2500 and warms the address).
        try interp.ctx.stack.push(test_addr);
        const cold_gas = try op_fn(&interp);
        try expectEqual(@as(u64, 2500), cold_gas);
        _ = try interp.ctx.stack.pop();

        // Second call - warm access (address already warmed, returns 0).
        try interp.ctx.stack.push(test_addr);
        const warm_gas = try op_fn(&interp);
        try expectEqual(@as(u64, 0), warm_gas);
        _ = try interp.ctx.stack.pop();
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

    const analyzed = try AnalyzedBytecode.initUncached(allocator, try allocator.dupe(u8, bytecode));
    const ctx = try CallContext.init(allocator, analyzed, Address.zero(), Address.zero(), U256.ZERO);
    var return_data: []const u8 = &[_]u8{};
    var interp = Interpreter.init(allocator, ctx, .{
        .spec = spec,
        .gas_limit = 1000000,
        .env = &env,
        .host = mock.host(),
        .return_data_buffer = &return_data,
        .is_static = false,
        .call_executor = CallExecutor.noOp(),
        .access_list = AccessList.Accessor.alwaysCold(),
    });
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

    const analyzed = try AnalyzedBytecode.initUncached(allocator, try allocator.dupe(u8, bytecode));
    const ctx = try CallContext.init(allocator, analyzed, Address.zero(), Address.zero(), U256.ZERO);
    var return_data: []const u8 = &[_]u8{};
    var interp = Interpreter.init(allocator, ctx, .{
        .spec = spec,
        .gas_limit = 1000000,
        .env = &env,
        .host = mock.host(),
        .return_data_buffer = &return_data,
        .is_static = false,
        .call_executor = CallExecutor.noOp(),
        .access_list = AccessList.Accessor.alwaysCold(),
    });
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
        var expected: u64 = copy_gas + expansion_gas;

        // EIP-2929: EXTCODECOPY has account access cost.
        if (tc.has_address) {
            // alwaysCold() returns true (cold), so we add cold access cost.
            expected +|= accountAccessCost(interp.spec, true);
        }

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
    const spec = Spec.forFork(.CANCUN);
    const very_large_size: usize = max_u64 / 4;
    const log_result = logCost(spec, 4, very_large_size);
    try expect(log_result == max_u64);

    // Note: calldataCost accumulation overflow is impractical to test
    // (would require ~270 PB allocation). The +|= operator is verified
    // by inspection and smaller tests verify the logic is correct.
}

test "CALL" {
    const allocator = std.testing.allocator;
    const bytecode = &[_]u8{0x00};
    const Env = @import("../context.zig").Env;
    const MockHost = @import("../host/mock.zig").MockHost;
    const env = Env.default();

    const TestCase = struct {
        fork: Hardfork = .CANCUN,
        // Stack values
        gas_limit: u64 = 10000,
        address: [20]u8 = [_]u8{0} ** 20,
        value: u64 = 0,
        args_offset: u64 = 0,
        args_size: u64 = 0,
        ret_offset: u64 = 0,
        ret_size: u64 = 0,
        // Setup: if non-null, create account with this balance.
        target_balance: ?u64 = null,
        // Expected cost breakdown (memory calculated dynamically).
        expected_access: u64,
        expected_value: u64 = 0,
        expected_new_account: u64 = 0,
    };

    const test_cases = [_]TestCase{
        // Cold access, no value, no memory expansion.
        .{
            .address = [_]u8{0} ** 18 ++ [_]u8{ 0x12, 0x34 },
            .expected_access = 2500,
        },
        // Value transfer to existing account.
        .{
            .address = [_]u8{0} ** 12 ++ [_]u8{ 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11 },
            .value = 100,
            .target_balance = 100,
            .expected_access = 2500,
            .expected_value = 9000,
        },
        // Value transfer to non-existent account (new account creation).
        .{
            .address = [_]u8{0} ** 18 ++ [_]u8{ 0x22, 0x22 },
            .value = 100,
            .expected_access = 2500,
            .expected_value = 9000,
            .expected_new_account = 25000,
        },
        // Memory expansion from args and ret regions.
        .{
            .address = [_]u8{0} ** 18 ++ [_]u8{ 0x33, 0x33 },
            .args_offset = 0,
            .args_size = 64,
            .ret_offset = 64,
            .ret_size = 32,
            .expected_access = 2500,
        },
        // Value transfer with memory expansion.
        .{
            .address = [_]u8{0} ** 18 ++ [_]u8{ 0x44, 0x44 },
            .value = 50,
            .args_size = 128,
            .target_balance = 1000,
            .expected_access = 2500,
            .expected_value = 9000,
        },
        // Zero-length regions at high offsets should not expand memory.
        .{
            .address = [_]u8{0} ** 18 ++ [_]u8{ 0x55, 0x55 },
            .args_offset = 1000,
            .args_size = 0,
            .ret_offset = 2000,
            .ret_size = 0,
            .expected_access = 2500,
        },
        // Overlapping memory regions (ret inside args).
        .{
            .address = [_]u8{0} ** 18 ++ [_]u8{ 0x66, 0x66 },
            .args_offset = 0,
            .args_size = 128,
            .ret_offset = 32,
            .ret_size = 64,
            .expected_access = 2500,
        },
        // Pre-Berlin: no dynamic gas (all costs in base opcode cost).
        .{
            .fork = .ISTANBUL,
            .address = [_]u8{0} ** 18 ++ [_]u8{ 0x77, 0x77 },
            .expected_access = 0,
        },
    };

    for (test_cases) |tc| {
        var mock = MockHost.init(allocator);
        defer mock.deinit();

        // Setup target account if specified.
        if (tc.target_balance) |balance| {
            const target = Address.init(tc.address);
            try mock.setBalance(target, U256.fromU64(balance));
        }

        const spec = Spec.forFork(tc.fork);
        const analyzed = try AnalyzedBytecode.initUncached(allocator, try allocator.dupe(u8, bytecode));
        const ctx = try CallContext.init(
            allocator,
            analyzed,
            Address.zero(),
            Address.zero(),
            U256.ZERO,
        );
        var return_data: []const u8 = &[_]u8{};
        var interp = Interpreter.init(allocator, ctx, .{
            .spec = spec,
            .gas_limit = 1000000,
            .env = &env,
            .host = mock.host(),
            .return_data_buffer = &return_data,
            .is_static = false,
            .call_executor = CallExecutor.noOp(),
            .access_list = AccessList.Accessor.alwaysCold(),
        });
        defer interp.deinit();

        // Push stack values (reverse order - LIFO).
        try interp.ctx.stack.push(U256.fromU64(tc.ret_size));
        try interp.ctx.stack.push(U256.fromU64(tc.ret_offset));
        try interp.ctx.stack.push(U256.fromU64(tc.args_size));
        try interp.ctx.stack.push(U256.fromU64(tc.args_offset));
        try interp.ctx.stack.push(U256.fromU64(tc.value));
        try interp.ctx.stack.push(U256.fromBeBytesPadded(&tc.address));
        try interp.ctx.stack.push(U256.fromU64(tc.gas_limit));

        const gas = try opCall(&interp);

        // Calculate expected gas with memory expansion.
        const args_end = if (tc.args_size > 0) tc.args_offset + tc.args_size else 0;
        const ret_end = if (tc.ret_size > 0) tc.ret_offset + tc.ret_size else 0;
        const max_end = @max(args_end, ret_end);
        const memory_cost = interp.gas.memoryExpansionCost(0, max_end);

        const expected = tc.expected_access + tc.expected_value + tc.expected_new_account + memory_cost;
        try expectEqual(expected, gas);

        // Cleanup stack.
        for (0..7) |_| {
            _ = try interp.ctx.stack.pop();
        }
    }
}
