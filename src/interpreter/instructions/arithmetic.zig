//! Arithmetic instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

/// Addition (ADD).
///
/// Stack: [..., a, b] -> [..., a + b]
/// Wraps on overflow (modulo 2^256)
pub inline fn add(stack: *Stack) !void {
    const b = try stack.pop();
    const a = try stack.pop();
    try stack.push(a.add(b));
}

/// Multiplication (MUL).
///
/// Stack: [..., a, b] -> [..., a * b]
/// Wraps on overflow (modulo 2^256)
pub inline fn mul(stack: *Stack) !void {
    const b = try stack.pop();
    const a = try stack.pop();
    try stack.push(a.mul(b));
}

/// Subtraction (SUB).
///
/// Stack: [..., a, b] -> [..., a - b]
/// Wraps on underflow (modulo 2^256)
pub inline fn sub(stack: *Stack) !void {
    const b = try stack.pop();
    const a = try stack.pop();
    try stack.push(a.sub(b));
}

/// Division (DIV).
///
/// Stack: [..., a, b] -> [..., a / b]
/// Division by zero returns 0 (EVM spec)
pub inline fn div(stack: *Stack) !void {
    const b = try stack.pop();
    const a = try stack.pop();
    const result = if (b.isZero()) U256.ZERO else a.div(b);
    try stack.push(result);
}

/// Modulo (MOD).
///
/// Stack: [..., a, b] -> [..., a % b]
/// Modulo by zero returns 0 (EVM spec)
pub inline fn mod(stack: *Stack) !void {
    const b = try stack.pop();
    const a = try stack.pop();
    const result = if (b.isZero()) U256.ZERO else a.rem(b);
    try stack.push(result);
}

/// Exponentiation (EXP).
///
/// Stack: [..., base, exponent] -> [..., base ^ exponent]
/// Note: This function only handles the stack operations.
/// Gas must be charged BEFORE calling this function:
/// - Base gas is charged in interpreter.step()
/// - Dynamic gas (based on exponent byte length) must be charged in execute()
pub inline fn exp(stack: *Stack) !void {
    const exponent = try stack.pop();
    const base = try stack.pop();
    const result = base.exp(exponent);
    try stack.push(result);
}

/// Sign extension (SIGNEXTEND).
///
/// Stack: [..., byte_num, value] -> [..., extended_value]
/// Extends the sign bit from position (byte_num * 8 + 7).
/// - byte_num: position of the sign byte (0 = rightmost/LSB, 31 = leftmost/MSB)
/// - If byte_num >= 31, returns value unchanged
/// - Otherwise, extends the sign bit at position (byte_num * 8 + 7) to all higher bits
pub inline fn signextend(stack: *Stack) !void {
    const byte_num_u256 = try stack.pop();
    const value = try stack.pop();

    // If byte_num doesn't fit in u64, return value unchanged
    const byte_num_u64 = byte_num_u256.toU64() orelse {
        try stack.push(value);
        return;
    };

    // Convert to u8; values >= 256 wrap (U256.signExtend handles >= 31 correctly)
    const byte_num_u8: u8 = @intCast(byte_num_u64 & 0xFF);
    const result = value.signExtend(byte_num_u8);

    try stack.push(result);
}

/// Signed division (SDIV).
///
/// Implements two's complement signed division.
/// Special cases are handled by U256.sdiv():
/// - Division by zero returns 0
/// - MIN_I256 / -1 returns MIN_I256 (overflow wraps)
///
/// Stack: [..., a, b] -> [..., a / b]
pub fn sdiv(stack: *Stack) !void {
    const b = try stack.pop();
    const a = try stack.pop();

    const result = a.sdiv(b);
    try stack.push(result);
}

/// Signed modulo (SMOD).
///
/// Implements two's complement signed modulo.
/// Special cases are handled by U256.srem():
/// - Modulo by zero returns 0
/// - MIN_I256 % -1 returns 0 (since MIN / -1 = MIN with remainder 0)
/// - Result takes the sign of the dividend
///
/// Stack: [..., a, b] -> [..., a % b]
pub fn smod(stack: *Stack) !void {
    const b = try stack.pop();
    const a = try stack.pop();

    const result = a.srem(b);
    try stack.push(result);
}

/// Modular addition (ADDMOD).
///
/// Computes (a + b) % N with proper overflow handling.
///
/// Stack: [..., a, b, N] -> [..., (a + b) % N]
pub fn addmod(stack: *Stack) !void {
    const n = try stack.pop();
    const b = try stack.pop();
    const a = try stack.pop();

    const result = a.addmod(b, n);
    try stack.push(result);
}

/// Modular multiplication (MULMOD).
///
/// Computes (a * b) % N with proper overflow handling.
/// Uses widening multiplication or reduction to avoid overflow.
///
/// Stack: [..., a, b, N] -> [..., (a * b) % N]
pub fn mulmod(stack: *Stack) !void {
    const n = try stack.pop();
    const b = try stack.pop();
    const a = try stack.pop();

    // Use U256's mulmod (already handles overflow correctly)
    const result = a.mulmod(b, n);
    try stack.push(result);
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "add: 2 + 3 = 5" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(2));
    try stack.push(U256.fromU64(3));
    try add(&stack);

    const result = try stack.pop();
    try expectEqual(5, result.toU64().?);
}

test "add: wrapping overflow" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.MAX);
    try stack.push(U256.fromU64(1));
    try add(&stack);

    const result = try stack.pop();
    try expect(result.isZero());
}

test "mul: 10 * 3 = 30" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(10));
    try stack.push(U256.fromU64(3));
    try mul(&stack);

    const result = try stack.pop();
    try expectEqual(30, result.toU64().?);
}

test "sub: 10 - 3 = 7" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(10));
    try stack.push(U256.fromU64(3));
    try sub(&stack);

    const result = try stack.pop();
    try expectEqual(7, result.toU64().?);
}

test "sub: wrapping underflow" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.ZERO);
    try stack.push(U256.fromU64(1));
    try sub(&stack);

    const result = try stack.pop();
    try expect(result.eql(U256.MAX));
}

test "div: 10 / 3 = 3" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(10));
    try stack.push(U256.fromU64(3));
    try div(&stack);

    const result = try stack.pop();
    try expectEqual(3, result.toU64().?);
}

test "div: division by zero returns 0" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(10));
    try stack.push(U256.ZERO);
    try div(&stack);

    const result = try stack.pop();
    try expect(result.isZero());
}

test "mod: 10 % 3 = 1" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(10));
    try stack.push(U256.fromU64(3));
    try mod(&stack);

    const result = try stack.pop();
    try expectEqual(1, result.toU64().?);
}

test "mod: modulo by zero returns 0" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(10));
    try stack.push(U256.ZERO);
    try mod(&stack);

    const result = try stack.pop();
    try expect(result.isZero());
}

test "exp: 2^8 = 256" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(2));
    try stack.push(U256.fromU64(8));
    try exp(&stack);

    const result = try stack.pop();
    try expectEqual(256, result.toU64().?);
}

test "signextend: byte 0 positive (0x7F)" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(0x7F)); // value: 0x7F (positive, bit 7 = 0)
    try stack.push(U256.ZERO); // byte_num: 0
    try signextend(&stack);

    const result = try stack.pop();
    try expectEqual(0x7F, result.toU64().?); // Should remain 0x7F
}

test "signextend: byte 0 negative (0xFF)" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(0xFF)); // value: 0xFF (negative, bit 7 = 1)
    try stack.push(U256.ZERO); // byte_num: 0
    try signextend(&stack);

    const result = try stack.pop();
    // Should extend to all 1s: 0xFFFF...FFFF
    try expect(result.eql(U256.MAX));
}

test "signextend: byte 1 positive (0x7FFF)" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(0x7FFF)); // value: 0x7FFF (positive at byte 1)
    try stack.push(U256.fromU64(1)); // byte_num: 1
    try signextend(&stack);

    const result = try stack.pop();
    try expectEqual(0x7FFF, result.toU64().?); // Should remain 0x7FFF
}

test "signextend: byte 1 negative (0x8FFF)" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(0x8FFF)); // value: 0x8FFF (bit 15 = 1)
    try stack.push(U256.fromU64(1)); // byte_num: 1
    try signextend(&stack);

    const result = try stack.pop();
    // Should extend bit 15 to ALL higher bits (including limbs 1-3)
    const expected = U256{ .limbs = .{ 0xFFFF_FFFF_FFFF_8FFF, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF } };
    try expect(result.eql(expected));
}

test "signextend: byte 3 clearing high bits" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    // Value with high bits set: 0xFF_00_00_00_7F_FF_FF_FF
    const value = U256{ .limbs = .{ 0x7FFF_FFFF, 0xFF00_0000, 0, 0 } };
    try stack.push(value);
    try stack.push(U256.fromU64(3)); // byte_num: 3
    try signextend(&stack);

    const result = try stack.pop();
    // Bit 31 (bit 7 of byte 3) is 1, so should extend
    // Actually 0x7F at byte 3 means bit 31 is 0 (positive)
    // So should clear all bits above bit 31: 0x7FFF_FFFF
    try expectEqual(0x7FFF_FFFF, result.toU64().?);
}

test "signextend: byte_num >= 31 returns unchanged" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    const value = U256.fromU64(0x1234_5678_90AB_CDEF);
    try stack.push(value);
    try stack.push(U256.fromU64(31)); // byte_num: 31
    try signextend(&stack);

    const result = try stack.pop();
    try expect(result.eql(value)); // Should be unchanged
}

test "signextend: byte_num > 31 returns unchanged" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    const value = U256.fromU64(0x1234_5678_90AB_CDEF);
    try stack.push(value);
    try stack.push(U256.fromU64(100)); // byte_num: 100
    try signextend(&stack);

    const result = try stack.pop();
    try expect(result.eql(value)); // Should be unchanged
}

test "signextend: byte_num very large returns unchanged" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    const value = U256.fromU64(0x1234_5678_90AB_CDEF);
    try stack.push(value);
    try stack.push(U256.MAX); // byte_num: huge number
    try signextend(&stack);

    const result = try stack.pop();
    try expect(result.eql(value)); // Should be unchanged
}

test "sdiv: basic signed division" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    // 10 / 3 = 3
    try stack.push(U256.fromU64(10));
    try stack.push(U256.fromU64(3));
    try sdiv(&stack);

    const result = try stack.pop();
    try expectEqual(3, result.toU64().?);
}

test "sdiv: division by zero returns 0" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(10));
    try stack.push(U256.ZERO);
    try sdiv(&stack);

    const result = try stack.pop();
    try expect(result.isZero());
}

test "sdiv: MIN / -1 returns MIN" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    const MIN_I256 = U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } };
    try stack.push(MIN_I256);
    try stack.push(U256.MAX); // -1 in two's complement
    try sdiv(&stack);

    const result = try stack.pop();
    try expect(result.eql(MIN_I256));
}

test "smod: basic signed modulo" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    // 10 % 3 = 1
    try stack.push(U256.fromU64(10));
    try stack.push(U256.fromU64(3));
    try smod(&stack);

    const result = try stack.pop();
    try expectEqual(1, result.toU64().?);
}

test "smod: modulo by zero returns 0" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(10));
    try stack.push(U256.ZERO);
    try smod(&stack);

    const result = try stack.pop();
    try expect(result.isZero());
}

test "smod: MIN % -1 returns 0" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    const MIN_I256 = U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } };
    try stack.push(MIN_I256);
    try stack.push(U256.MAX); // -1 in two's complement
    try smod(&stack);

    const result = try stack.pop();
    try expect(result.isZero());
}

test "addmod: basic modular addition" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    // (5 + 7) % 10 = 2
    try stack.push(U256.fromU64(5));
    try stack.push(U256.fromU64(7));
    try stack.push(U256.fromU64(10));
    try addmod(&stack);

    const result = try stack.pop();
    try expectEqual(2, result.toU64().?);
}

test "addmod: modulo by zero returns 0" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(5));
    try stack.push(U256.fromU64(7));
    try stack.push(U256.ZERO);
    try addmod(&stack);

    const result = try stack.pop();
    try expect(result.isZero());
}

test "mulmod: basic modular multiplication" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    // (5 * 7) % 10 = 5
    try stack.push(U256.fromU64(5));
    try stack.push(U256.fromU64(7));
    try stack.push(U256.fromU64(10));
    try mulmod(&stack);

    const result = try stack.pop();
    try expectEqual(5, result.toU64().?);
}

test "mulmod: modulo by zero returns 0" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(5));
    try stack.push(U256.fromU64(7));
    try stack.push(U256.ZERO);
    try mulmod(&stack);

    const result = try stack.pop();
    try expect(result.isZero());
}
