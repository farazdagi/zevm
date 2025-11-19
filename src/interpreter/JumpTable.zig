//! Jump table for validating JUMPDEST positions in EVM bytecode.
//!
//! This module provides efficient O(1) lookup for valid jump destinations
//! using a bitvector representation. The analysis is O(n) in bytecode length.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Opcode = @import("opcode.zig").Opcode;
const B256 = @import("../primitives/mod.zig").B256;

const JumpTable = @This();

/// Bitvector where bit n is set if position n is a valid JUMPDEST.
bits: []u8,

/// Length of the original bytecode.
len: usize,

/// Allocator used for memory management.
allocator: Allocator,

/// Cache type for storing analyzed jump tables by code hash.
pub const Cache = std.AutoHashMap(B256, JumpTable);

/// Analyze bytecode to find all valid JUMPDEST positions.
///
/// Scans bytecode sequentially, skipping PUSH immediate data,
/// and marks each JUMPDEST position in the bitvector.
///
/// Time complexity: O(n) where n is bytecode length.
/// Space complexity: O(n/8) for the bitvector.
pub fn analyze(allocator: Allocator, bytecode: []const u8) !JumpTable {
    // Return empty jump table for codeless bytecode.
    if (bytecode.len == 0) {
        return empty(allocator);
    }

    // Allocate bitvector (1 bit per bytecode position).
    const num_bytes = (bytecode.len + 7) / 8;
    const bits = try allocator.alloc(u8, num_bytes);
    @memset(bits, 0);

    var i: usize = 0;
    while (i < bytecode.len) {
        // Skip invalid opcodes.
        if (!Opcode.isDefined(bytecode[i])) {
            i += 1;
            continue;
        }

        const opcode = Opcode.fromByte(bytecode[i]);
        if (opcode == .JUMPDEST) {
            // Set bit for this position.
            bits[i >> 3] |= @as(u8, 1) << @intCast(i & 7);
        }

        // Skip PUSH immediate data.
        i += if (opcode.isPush()) 1 + opcode.pushSize() else 1;
    }

    return .{
        .bits = bits,
        .len = bytecode.len,
        .allocator = allocator,
    };
}

/// Check if a position is a valid jump destination.
pub fn isValidDest(self: JumpTable, pc: usize) bool {
    if (pc >= self.len) return false;
    return (self.bits[pc >> 3] & (@as(u8, 1) << @intCast(pc & 7))) != 0;
}

/// Clone this jump table with a new allocator.
pub fn clone(self: JumpTable, allocator: Allocator) !JumpTable {
    if (self.bits.len == 0) {
        return empty(allocator);
    }

    const bits_copy = try allocator.alloc(u8, self.bits.len);
    @memcpy(bits_copy, self.bits);

    return .{
        .bits = bits_copy,
        .len = self.len,
        .allocator = allocator,
    };
}

/// Free allocated resources.
pub fn deinit(self: JumpTable) void {
    if (self.bits.len > 0) {
        self.allocator.free(self.bits);
    }
}

/// Create an empty jump table (for codeless accounts).
pub fn empty(allocator: Allocator) JumpTable {
    return .{
        .bits = &[_]u8{},
        .len = 0,
        .allocator = allocator,
    };
}

/// Compute Keccak256 hash of bytecode (for cache key).
pub fn computeCodeHash(bytecode: []const u8) B256 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(bytecode, &hash, .{});
    return B256.init(hash);
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Analyze" {
    const TestCase = struct {
        bytecode: []const u8,
        valid: []const usize,
        invalid: []const usize,
    };

    // PUSH32 followed by 32 bytes of 0x5B (JUMPDEST byte), then real JUMPDEST.
    const push32_bytecode = comptime blk: {
        var bc: [34]u8 = undefined;
        bc[0] = 0x7F; // PUSH32
        for (0..32) |i| bc[1 + i] = 0x5B;
        bc[33] = 0x5B; // Real JUMPDEST
        break :blk bc;
    };

    const cases = [_]TestCase{
        // PUSH1 0x05, JUMP, INVALID, INVALID, JUMPDEST, STOP
        .{
            .bytecode = &.{ 0x60, 0x05, 0x56, 0xFE, 0xFE, 0x5B, 0x00 },
            .valid = &.{5},
            .invalid = &.{ 0, 1, 2, 3, 4, 6 },
        },
        // PUSH2 0x5B5B (fake JUMPDESTs in immediate), JUMPDEST
        .{
            .bytecode = &.{ 0x61, 0x5B, 0x5B, 0x5B },
            .valid = &.{3},
            .invalid = &.{ 1, 2 },
        },
        // JUMPDEST, PUSH1 0x05, JUMPDEST, PUSH1 0x00, JUMPDEST
        .{
            .bytecode = &.{ 0x5B, 0x60, 0x05, 0x5B, 0x60, 0x00, 0x5B },
            .valid = &.{ 0, 3, 6 },
            .invalid = &.{ 1, 2, 4, 5 },
        },
        // PUSH32 with fake JUMPDESTs in immediate
        .{
            .bytecode = &push32_bytecode,
            .valid = &.{33},
            .invalid = &.{ 0, 1, 16, 32 },
        },
        // Empty bytecode
        .{
            .bytecode = &.{},
            .valid = &.{},
            .invalid = &.{0},
        },
        // Out of bounds checks
        .{
            .bytecode = &.{ 0x5B, 0x00 },
            .valid = &.{0},
            .invalid = &.{ 2, 100 },
        },
    };

    for (cases) |case| {
        var jt = try analyze(std.testing.allocator, case.bytecode);
        defer jt.deinit();

        for (case.valid) |pos| try expect(jt.isValidDest(pos));
        for (case.invalid) |pos| try expect(!jt.isValidDest(pos));
    }
}

test "Clone" {
    const bytecode = [_]u8{ 0x5B, 0x60, 0x03, 0x5B };
    var jt = try analyze(std.testing.allocator, &bytecode);
    defer jt.deinit();

    var cloned = try jt.clone(std.testing.allocator);
    defer cloned.deinit();

    // Cloned should have same valid destinations.
    try expect(cloned.isValidDest(0));
    try expect(!cloned.isValidDest(1));
    try expect(!cloned.isValidDest(2));
    try expect(cloned.isValidDest(3));
    try expectEqual(jt.len, cloned.len);
}

test "Compute hash" {
    const bytecode = [_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 };
    const hash = computeCodeHash(&bytecode);

    // Hash should be deterministic.
    const hash2 = computeCodeHash(&bytecode);
    try expect(hash.eql(hash2));

    // Different bytecode should produce different hash.
    const other_bytecode = [_]u8{ 0x60, 0x03, 0x60, 0x04, 0x01 };
    const other_hash = computeCodeHash(&other_bytecode);
    try expect(!hash.eql(other_hash));
}
