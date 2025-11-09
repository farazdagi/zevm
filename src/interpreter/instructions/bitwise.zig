//! Bitwise instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

/// Bitwise AND.
///
/// Stack: [a, b, ...] -> [a & b, ...]
pub inline fn opAnd(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.peekMut(0);
    b.* = a.bitAnd(b.*);
}

/// Bitwise OR.
///
/// Stack: [a, b, ...] -> [a | b, ...]
pub inline fn opOr(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.peekMut(0);
    b.* = a.bitOr(b.*);
}

/// Bitwise XOR.
///
/// Stack: [a, b, ...] -> [a ^ b, ...]
pub inline fn opXor(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.peekMut(0);
    b.* = a.bitXor(b.*);
}

/// Bitwise NOT.
///
/// Stack: [a, ...] -> [~a, ...]
pub inline fn opNot(stack: *Stack) !void {
    const a = try stack.peekMut(0);
    a.* = a.bitNot();
}

/// Extract byte from word.
///
/// Stack: [i, x, ...] -> [byte_i(x), ...]
/// Returns the i-th byte of x (index 0 is most significant byte, big-endian).
/// Returns 0 if i >= 32.
pub inline fn opByte(stack: *Stack) !void {
    const i_u256 = try stack.pop();
    const x = try stack.peekMut(0);

    // Convert index to u8, handling out of bounds
    const i_u8: u8 = if (i_u256.toU64()) |val|
        if (val < 32) @intCast(val) else 32
    else
        32; // If doesn't fit in u64, it's >= 32

    const byte_val = x.byte(i_u8);
    x.set(byte_val);
}

/// Shift left (SHL).
///
/// Stack: [shift, value, ...] -> [value << shift, ...]
/// All values treated as unsigned.
/// If shift >= 256, result is 0.
pub inline fn opShl(stack: *Stack) !void {
    const shift_u256 = try stack.pop();
    const value = try stack.peekMut(0);

    // Convert shift to u32, capping at 256
    const shift: u32 = if (shift_u256.toU64()) |val|
        if (val <= 256) @intCast(val) else 256
    else
        256; // If doesn't fit in u64, it's >= 256

    value.set(value.shl(shift));
}

/// Logical shift right (SHR).
///
/// Stack: [shift, value, ...] -> [value >> shift, ...]
/// Zero-fills on the left (logical shift).
/// If shift >= 256, result is 0.
pub inline fn opShr(stack: *Stack) !void {
    const shift_u256 = try stack.pop();
    const value = try stack.peekMut(0);

    const shift: u32 = if (shift_u256.toU64()) |val|
        if (val <= 256) @intCast(val) else 256
    else
        256;

    value.set(value.shr(shift));
}

/// Arithmetic shift right (SAR).
///
/// Stack: [shift, value, ...] -> [value >> shift (signed), ...]
/// Sign-extends on the left (arithmetic shift).
/// If shift >= 256:
///   - Returns 0 if value >= 0 (MSB = 0)
///   - Returns MAX if value < 0 (MSB = 1)
pub inline fn opSar(stack: *Stack) !void {
    const shift_u256 = try stack.pop();
    const value = try stack.peekMut(0);

    const shift: u32 = if (shift_u256.toU64()) |val|
        if (val <= 256) @intCast(val) else 256
    else
        256;

    value.set(value.sar(shift));
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const test_helpers = @import("test_helpers.zig");
const TestCase = test_helpers.TestCase;
const testOp = test_helpers.testOp;
const t = test_helpers.TestCase.binaryCase;
const tu = test_helpers.TestCase.unaryCase;

test "AND" {
    const test_cases = [_]TestCase{
        t(0xFF, 0xAA, 0xAA),
        t(0xF0, 0x0F, 0x00),
        t(0xFF, 0xFF, 0xFF),
        t(0xFF, 0x00, 0x00),
        t(U256.MAX, U256.ZERO, 0),
        t(U256.MAX, U256.MAX, U256.MAX),
    };

    try testOp(&opAnd, &test_cases);
}

test "OR" {
    const test_cases = [_]TestCase{
        t(0xFF, 0xAA, 0xFF),
        t(0xF0, 0x0F, 0xFF),
        t(0x00, 0x00, 0x00),
        t(0xAA, 0x55, 0xFF),
    };

    try testOp(&opOr, &test_cases);
}

test "XOR" {
    const test_cases = [_]TestCase{
        t(0xFF, 0xAA, 0x55),
        t(0xF0, 0x0F, 0xFF),
        t(0xAA, 0xAA, 0x00),
        t(0xFF, 0x00, 0xFF),
    };

    try testOp(&opXor, &test_cases);
}

test "NOT" {
    const test_cases = [_]TestCase{
        tu(U256.ZERO, U256.MAX),
        tu(U256.MAX, 0),
        tu(0xFF, U256{ .limbs = .{ 0xFFFFFFFFFFFFFF00, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } }),
    };

    try testOp(&opNot, &test_cases);
}

test "BYTE" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    // Create a known value: 0x0102030405060708...
    const val = U256{
        .limbs = .{
            0x1F1E1D1C1B1A1918, // bytes 24-31
            0x1716151413121110, // bytes 16-23
            0x0F0E0D0C0B0A0908, // bytes 8-15
            0x0706050403020100, // bytes 0-7
        },
    };

    // Extract byte 0 (most significant) = 0x07
    try stack.push(val); // x first
    try stack.push(U256.fromU64(0)); // i second (on top)
    try opByte(&stack);
    const result0 = try stack.pop();
    try expectEqual(0x07, result0.toU64().?);

    // Extract byte 1 = 0x06
    try stack.push(val);
    try stack.push(U256.fromU64(1));
    try opByte(&stack);
    const result1 = try stack.pop();
    try expectEqual(0x06, result1.toU64().?);

    // Extract byte 31 (least significant) = 0x18
    try stack.push(val);
    try stack.push(U256.fromU64(31));
    try opByte(&stack);
    const result31 = try stack.pop();
    try expectEqual(0x18, result31.toU64().?);

    // Extract byte 32 (out of bounds) = 0
    try stack.push(val);
    try stack.push(U256.fromU64(32));
    try opByte(&stack);
    const result_oob = try stack.pop();
    try expectEqual(0, result_oob.toU64().?);
}

test "SHL" {
    const test_cases = [_]TestCase{
        t(0, 1, 1),
        t(8, 1, 256),
        t(4, 0xFF, 0xFF0),
        t(3, 5, 40),
        t(256, 1, 0),
    };

    try testOp(&opShl, &test_cases);
}

test "SHR" {
    const test_cases = [_]TestCase{
        t(0, 256, 256),
        t(8, 256, 1),
        t(8, 0xFF00, 0xFF),
        t(3, 40, 5),
        t(256, U256.MAX, 0),
    };

    try testOp(&opShr, &test_cases);
}

test "SAR" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    // Positive values (like SHR)
    const positive_cases = [_]struct {
        value: u64,
        shift: u32,
        expected: u64,
    }{
        .{ .value = 256, .shift = 8, .expected = 1 },
        .{ .value = 0xFF00, .shift = 8, .expected = 0xFF },
    };

    for (positive_cases) |tc| {
        try stack.push(U256.fromU64(tc.value));
        try stack.push(U256.fromU64(tc.shift));
        try opSar(&stack);
        const result = try stack.pop();
        try expectEqual(tc.expected, result.toU64().?);
        try expectEqual(0, stack.len);
    }

    // Negative value - sign extension
    const MIN_I256 = U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } };
    try stack.push(MIN_I256);
    try stack.push(U256.fromU64(8));
    try opSar(&stack);
    const result_neg = try stack.pop();
    try expectEqual(0xFF80000000000000, result_neg.limbs[3]);

    // Overflow cases
    // Positive value shifted by >= 256 = 0
    try stack.push(U256.fromU64(123));
    try stack.push(U256.fromU64(300));
    try opSar(&stack);
    const result_pos_overflow = try stack.pop();
    try expect(result_pos_overflow.isZero());

    // Negative value shifted by >= 256 = MAX
    try stack.push(U256.MAX);
    try stack.push(U256.fromU64(300));
    try opSar(&stack);
    const result_neg_overflow = try stack.pop();
    try expect(result_neg_overflow.eql(U256.MAX));
}
