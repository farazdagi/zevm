//! Memory operations instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Load word from memory (MLOAD).
///
/// Stack: [offset, ...] -> [value, ...]
/// Gas is charged in interpreter before calling this function.
pub fn opMload(interp: *Interpreter) !void {
    const offset_ptr = try interp.ctx.stack.peekMut(0);
    const offset = offset_ptr.toUsize() orelse return error.InvalidOffset;

    offset_ptr.* = try interp.ctx.memory.mload(offset);
}

/// Store word to memory (MSTORE).
///
/// Stack: [offset, value, ...] -> [...]
/// Gas is charged in interpreter before calling this function.
pub fn opMstore(interp: *Interpreter) !void {
    const offset_u256 = try interp.ctx.stack.pop();
    const value = try interp.ctx.stack.pop();
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;

    try interp.ctx.memory.mstore(offset, value);
}

/// Store byte to memory (MSTORE8).
///
/// Stack: [offset, value, ...] -> [...]
/// Gas is charged in interpreter before calling this function.
pub fn opMstore8(interp: *Interpreter) !void {
    const offset_u256 = try interp.ctx.stack.pop();
    const value_u256 = try interp.ctx.stack.pop();
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;

    // Extract least significant byte
    const byte: u8 = @truncate(value_u256.toU64() orelse 0);

    try interp.ctx.memory.mstore8(offset, byte);
}

/// Get size of active memory in bytes (MSIZE).
///
/// Stack: [...] -> [size, ...]
pub fn opMsize(interp: *Interpreter) !void {
    const size = interp.ctx.memory.len();
    try interp.ctx.stack.push(U256.fromU64(@intCast(size)));
}

/// Copy memory (MCOPY) - EIP-5656, Cancun+.
///
/// Stack: [dest_offset, src_offset, length, ...] -> [...]
/// Copies length bytes from src_offset to dest_offset within memory.
/// Handles overlapping regions correctly (memmove semantics).
/// Gas is charged in interpreter before calling this function.
pub fn opMcopy(interp: *Interpreter) !void {
    // Pop operands (dest first per EVM stack convention)
    const dest_u256 = try interp.ctx.stack.pop();
    const src_u256 = try interp.ctx.stack.pop();
    const length_u256 = try interp.ctx.stack.pop();

    // Convert to usize with overflow check.
    const dest = dest_u256.toUsize() orelse return error.InvalidOffset;
    const src = src_u256.toUsize() orelse return error.InvalidOffset;
    const length = length_u256.toUsize() orelse return error.InvalidOffset;

    // Handle zero-length case (no-op).
    if (length == 0) return;

    // Calculate end positions with overflow check
    const dest_end = std.math.add(usize, dest, length) catch return error.InvalidOffset;
    const src_end = std.math.add(usize, src, length) catch return error.InvalidOffset;

    // Ensure memory is large enough for both source and destination
    const max_end = @max(dest_end, src_end);
    try interp.ctx.memory.ensureCapacity(0, max_end);

    // Copy with memmove semantics to handle overlapping regions
    // std.mem.copyForwards and copyBackwards handle overlapping correctly
    const mem_slice = interp.ctx.memory.data.items;
    if (dest <= src) {
        // Copy forwards (safe for dest < src or no overlap)
        std.mem.copyForwards(u8, mem_slice[dest..dest_end], mem_slice[src..src_end]);
    } else {
        // Copy backwards (safe for dest > src to avoid overwriting source)
        std.mem.copyBackwards(u8, mem_slice[dest..dest_end], mem_slice[src..src_end]);
    }
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const test_helpers = @import("test_helpers.zig");

test "MSTORE and MLOAD basic operations" {
    var ctx = try test_helpers.TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // MSTORE: store 0x42 at offset 0
    try ctx.interp.ctx.stack.push(U256.fromU64(0x42)); // value
    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // offset
    try opMstore(&ctx.interp);

    // MLOAD: load from offset 0
    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // offset
    try opMload(&ctx.interp);
    const loaded = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(0x42), loaded);
}

test "MSTORE8 byte storage" {
    var ctx = try test_helpers.TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // MSTORE8: store byte 0x42 at offset 5
    try ctx.interp.ctx.stack.push(U256.fromU64(0x1234)); // value (only LSB 0x34 stored)
    try ctx.interp.ctx.stack.push(U256.fromU64(5)); // offset
    try opMstore8(&ctx.interp);

    // Verify by loading the word containing it
    const loaded_word = try ctx.interp.ctx.memory.mload(0);
    const loaded_bytes = loaded_word.toBeBytes();
    try expectEqual(0x34, loaded_bytes[5]);
}

test "MSIZE reports correct size" {
    var ctx = try test_helpers.TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // Initially empty
    try opMsize(&ctx.interp);
    try expectEqual(0, (try ctx.interp.ctx.stack.pop()).toU64().?);

    // After storing at offset 0 (expands to 32 bytes)
    try ctx.interp.ctx.memory.mstore(0, U256.fromU64(0x42));
    try opMsize(&ctx.interp);
    try expectEqual(32, (try ctx.interp.ctx.stack.pop()).toU64().?);
}

test "MCOPY basic copy" {
    var ctx = try test_helpers.TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // Setup: store value at offset 0
    try ctx.interp.ctx.memory.mstore(0, U256.fromU64(0x1234));

    // MCOPY: copy from 0 to 32 for 32 bytes
    try ctx.interp.ctx.stack.push(U256.fromU64(32)); // length
    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // src
    try ctx.interp.ctx.stack.push(U256.fromU64(32)); // dest
    try opMcopy(&ctx.interp);

    // Verify the copy
    const copied = try ctx.interp.ctx.memory.mload(32);
    try expectEqual(U256.fromU64(0x1234), copied);
}

test "MCOPY overlapping regions" {
    var ctx = try test_helpers.TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // Setup: Store pattern [0xAA, 0xBB, 0xCC, 0xDD] at offset 0
    try ctx.interp.ctx.memory.mstore8(0, 0xAA);
    try ctx.interp.ctx.memory.mstore8(1, 0xBB);
    try ctx.interp.ctx.memory.mstore8(2, 0xCC);
    try ctx.interp.ctx.memory.mstore8(3, 0xDD);

    // Copy from offset 0 to offset 2 (overlapping, forward)
    try ctx.interp.ctx.stack.push(U256.fromU64(2)); // length
    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // src
    try ctx.interp.ctx.stack.push(U256.fromU64(2)); // dest
    try opMcopy(&ctx.interp);

    // Verify the copy
    const slice = try ctx.interp.ctx.memory.getSlice(0, 4);
    try expectEqual(0xAA, slice[0]);
    try expectEqual(0xBB, slice[1]);
    try expectEqual(0xAA, slice[2]);
    try expectEqual(0xBB, slice[3]);
}

test "MCOPY zero-length is no-op" {
    var ctx = try test_helpers.TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // Store value at offset 0
    try ctx.interp.ctx.memory.mstore(0, U256.fromU64(0x42));
    const initial_size = ctx.interp.ctx.memory.len();

    // Zero-length copy should be no-op
    try ctx.interp.ctx.stack.push(U256.ZERO); // length = 0
    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // src
    try ctx.interp.ctx.stack.push(U256.fromU64(32)); // dest
    try opMcopy(&ctx.interp);

    // Memory size should not change
    try expectEqual(initial_size, ctx.interp.ctx.memory.len());
}
