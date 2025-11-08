//! Arithmetic instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

/// Addition (ADD).
///
/// Stack: [a, b, ...] -> [a + b, ...]
/// Wraps on overflow (modulo 2^256)
pub inline fn add(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.pop();

    const result = a.add(b);
    try stack.push(result);
}

/// Multiplication (MUL).
///
/// Stack: [a, b, ...] -> [a * b, ...]
/// Wraps on overflow (modulo 2^256)
pub inline fn mul(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.pop();

    const result = a.mul(b);
    try stack.push(result);
}

/// Subtraction (SUB).
///
/// Stack: [a, b, ...] -> [a - b, ...]
/// Wraps on underflow (modulo 2^256)
pub inline fn sub(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.pop();

    const result = a.sub(b);
    try stack.push(result);
}

/// Division (DIV).
///
/// Stack: [a, b, ...] -> [a // b, ...]
/// Division by zero returns 0 (EVM spec)
pub inline fn div(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.pop();

    const result = a.div(b);
    try stack.push(result);
}

/// Modulo (MOD).
///
/// Stack: [a, b, ...] -> [a % b, ...]
/// Modulo by zero returns 0 (EVM spec)
pub inline fn mod(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.pop();

    const result = a.rem(b);
    try stack.push(result);
}

/// Exponentiation (EXP).
///
/// Stack: [base, exponent, ...] -> [base ^ exponent, ...]
/// Note: This function only handles the stack operations.
/// Gas must be charged BEFORE calling this function:
/// - Base gas is charged in interpreter.step()
/// - Dynamic gas (based on exponent byte length) must be charged in execute()
pub inline fn exp(stack: *Stack) !void {
    const base = try stack.pop();
    const exponent = try stack.pop();

    const result = base.exp(exponent);
    try stack.push(result);
}

/// Sign extension (SIGNEXTEND).
///
/// Stack: [value, byte_num, ...] -> [signextend(value, byte_num), ...]
/// Extends the sign bit from position (byte_num * 8 + 7).
/// - byte_num: position of the sign byte (0 = rightmost/LSB, 31 = leftmost/MSB)
/// - If byte_num >= 31, returns value unchanged
/// - Otherwise, extends the sign bit at position (byte_num * 8 + 7) to all higher bits
pub inline fn signextend(stack: *Stack) !void {
    const value = try stack.pop();
    const byte_num_u256 = try stack.pop();

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
/// Stack: [a, b, ...] -> [a / b, ...]
pub fn sdiv(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.pop();

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
/// Stack: [a, b, ...] -> [a % b, ...]
pub fn smod(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.pop();

    const result = a.srem(b);
    try stack.push(result);
}

/// Modular addition (ADDMOD).
///
/// Computes (a + b) % N with proper overflow handling.
///
/// Stack: [a, b, N, ...] -> [(a + b) % N, ...]
pub fn addmod(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.pop();
    const n = try stack.pop();

    const result = a.addmod(b, n);
    try stack.push(result);
}

/// Modular multiplication (MULMOD).
///
/// Computes (a * b) % N with proper overflow handling.
/// Uses widening multiplication or reduction to avoid overflow.
///
/// Stack: [a, b, N, ...] -> [(a * b) % N, ...]
pub fn mulmod(stack: *Stack) !void {
    const a = try stack.pop();
    const b = try stack.pop();
    const n = try stack.pop();

    const result = a.mulmod(b, n);
    try stack.push(result);
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

test "add" {
    const test_cases = [_]TestCase{
        // 2 + 3 = 5
        t(2, 3, 5),
        // MAX + 1 = 0 (wrapping overflow)
        t(U256.MAX, 1, 0),
    };
    try testOp(&add, &test_cases);
}

test "mul" {
    const test_cases = [_]TestCase{
        // 10 * 3 = 30
        t(10, 3, 30),
    };
    try testOp(&mul, &test_cases);
}

test "sub" {
    const test_cases = [_]TestCase{
        // 10 - 3 = 7
        t(10, 3, 7),
        // 0 - 1 = MAX (wrapping underflow)
        t(0, 1, U256.MAX),
    };
    try testOp(&sub, &test_cases);
}

test "div" {
    const test_cases = [_]TestCase{
        // 10 / 3 = 3
        t(10, 3, 3),
        // 10 / 0 = 0 (division by zero)
        t(10, 0, 0),
    };
    try testOp(&div, &test_cases);
}

test "mod" {
    const test_cases = [_]TestCase{
        // 10 % 3 = 1
        t(10, 3, 1),
        // 10 % 0 = 0 (modulo by zero)
        t(10, 0, 0),
    };
    try testOp(&mod, &test_cases);
}

test "exp" {
    const test_cases = [_]TestCase{
        // 2^8 = 256
        t(2, 8, 256),
    };
    try testOp(&exp, &test_cases);
}

test "signextend" {
    const test_cases = [_]TestCase{
        // byte 0 positive - remains 0x7F
        t(0x7F, 0, 0x7F),
        // byte 0 negative - extends to all 1s
        t(0xFF, 0, U256.MAX),
        // byte 1 positive - remains 0x7FFF
        t(0x7FFF, 1, 0x7FFF),
        // byte 1 negative (0x8FFF) - extends sign bit to all higher bits
        t(0x8FFF, 1, U256{ .limbs = .{ 0xFFFF_FFFF_FFFF_8FFF, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF } }),
        // byte 3 with high bits set - clears high bits (sign bit is 0)
        t(U256{ .limbs = .{ 0x7FFF_FFFF, 0xFF00_0000, 0, 0 } }, 3, 0x7FFF_FFFF),
        // byte_num >= 31 - unchanged
        t(0x1234_5678_90AB_CDEF, 31, 0x1234_5678_90AB_CDEF),
        // byte_num > 31 - unchanged
        t(0x1234_5678_90AB_CDEF, 100, 0x1234_5678_90AB_CDEF),
    };
    try testOp(&signextend, &test_cases);
}

test "sdiv" {
    const test_cases = [_]TestCase{
        // 10 / 3 = 3
        t(10, 3, 3),
        // 10 / 0 = 0 (division by zero)
        t(10, 0, 0),
        // MIN_I256 / -1 = MIN_I256 (overflow wraps)
        t(U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } }, U256.MAX, U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } }),
    };
    try testOp(&sdiv, &test_cases);
}

test "smod" {
    const test_cases = [_]TestCase{
        // 10 % 3 = 1
        t(10, 3, 1),
        // 10 % 0 = 0 (modulo by zero)
        t(10, 0, 0),
        // MIN_I256 % -1 = 0 (overflow case)
        t(U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } }, U256.MAX, 0),
    };
    try testOp(&smod, &test_cases);
}

test "addmod" {
    const test_cases = [_]TestCase{
        // (5 + 7) % 10 = 2
        TestCase.ternaryCase(5, 7, 10, 2),
        // (5 + 7) % 0 = 0 (modulo by zero)
        TestCase.ternaryCase(5, 7, 0, 0),
    };
    try testOp(&addmod, &test_cases);
}

test "mulmod" {
    const test_cases = [_]TestCase{
        // (5 * 7) % 10 = 5
        TestCase.ternaryCase(5, 7, 10, 5),
        // (5 * 7) % 0 = 0 (modulo by zero)
        TestCase.ternaryCase(5, 7, 0, 0),
    };
    try testOp(&mulmod, &test_cases);
}
