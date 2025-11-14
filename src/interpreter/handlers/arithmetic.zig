//! Arithmetic instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Addition (ADD).
///
/// Stack: [a, b, ...] -> [a + b, ...]
/// Wraps on overflow (modulo 2^256)
pub fn opAdd(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.* = a.add(b.*);
}

/// Multiplication (MUL).
///
/// Stack: [a, b, ...] -> [a * b, ...]
/// Wraps on overflow (modulo 2^256)
pub fn opMul(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.* = a.mul(b.*);
}

/// Subtraction (SUB).
///
/// Stack: [a, b, ...] -> [a - b, ...]
/// Wraps on underflow (modulo 2^256)
pub fn opSub(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.* = a.sub(b.*);
}

/// Division (DIV).
///
/// Stack: [a, b, ...] -> [a // b, ...]
/// Division by zero returns 0 (EVM spec)
pub fn opDiv(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.* = a.div(b.*);
}

/// Modulo (MOD).
///
/// Stack: [a, b, ...] -> [a % b, ...]
/// Modulo by zero returns 0 (EVM spec)
pub fn opMod(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.* = a.rem(b.*);
}

/// Exponentiation (EXP).
///
/// Stack: [base, exponent, ...] -> [base ^ exponent, ...]
/// Note: This function only handles the stack operations.
/// Gas must be charged BEFORE calling this function:
/// - Base gas is charged in interpreter.step()
/// - Dynamic gas (based on exponent byte length) must be charged in execute()
pub fn opExp(interp: *Interpreter) !void {
    const base = try interp.ctx.stack.pop();
    const exponent = try interp.ctx.stack.peekMut(0);
    exponent.* = base.exp(exponent.*);
}

/// Sign extension (SIGNEXTEND).
///
/// Stack: [value, byte_num, ...] -> [signextend(value, byte_num), ...]
/// Extends the sign bit from position (byte_num * 8 + 7).
/// - byte_num: position of the sign byte (0 = rightmost/LSB, 31 = leftmost/MSB)
/// - If byte_num >= 31, returns value unchanged
/// - Otherwise, extends the sign bit at position (byte_num * 8 + 7) to all higher bits
pub fn opSignextend(interp: *Interpreter) !void {
    const value = try interp.ctx.stack.pop();
    const byte_num_u256 = try interp.ctx.stack.peekMut(0);

    // If byte_num doesn't fit in u64, return value unchanged
    const byte_num_u64 = byte_num_u256.toU64() orelse {
        byte_num_u256.* = value;
        return;
    };

    // Convert to u8; values >= 256 wrap (U256.signExtend handles >= 31 correctly)
    const byte_num_u8 = @as(u8, @intCast(byte_num_u64 & 0xFF));
    byte_num_u256.* = value.signExtend(byte_num_u8);
}

/// Signed division (SDIV).
///
/// Implements two's complement signed division.
/// Special cases are handled by U256.sdiv():
/// - Division by zero returns 0
/// - MIN_I256 / -1 returns MIN_I256 (overflow wraps)
///
/// Stack: [a, b, ...] -> [a / b, ...]
pub fn opSdiv(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.* = a.sdiv(b.*);
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
pub fn opSmod(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.* = a.srem(b.*);
}

/// Modular addition (ADDMOD).
///
/// Computes (a + b) % N with proper overflow handling.
///
/// Stack: [a, b, N, ...] -> [(a + b) % N, ...]
pub fn opAddmod(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.pop();
    const n = try interp.ctx.stack.peekMut(0);
    n.* = a.addmod(b, n.*);
}

/// Modular multiplication (MULMOD).
///
/// Computes (a * b) % N with proper overflow handling.
/// Uses widening multiplication or reduction to avoid overflow.
///
/// Stack: [a, b, N, ...] -> [(a * b) % N, ...]
pub fn opMulmod(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.pop();
    const n = try interp.ctx.stack.peekMut(0);
    n.* = a.mulmod(b, n.*);
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

test "ADD" {
    const test_cases = [_]TestCase{
        // 2 + 3 = 5
        t(2, 3, 5),
        // MAX + 1 = 0 (wrapping overflow)
        t(U256.MAX, 1, 0),
    };
    try testOp(&opAdd, &test_cases);
}

test "MUL" {
    const test_cases = [_]TestCase{
        // 10 * 3 = 30
        t(10, 3, 30),
    };
    try testOp(&opMul, &test_cases);
}

test "SUB" {
    const test_cases = [_]TestCase{
        // 10 - 3 = 7
        t(10, 3, 7),
        // 0 - 1 = MAX (wrapping underflow)
        t(0, 1, U256.MAX),
    };
    try testOp(&opSub, &test_cases);
}

test "DIV" {
    const test_cases = [_]TestCase{
        // 10 / 3 = 3
        t(10, 3, 3),
        // 10 / 0 = 0 (division by zero)
        t(10, 0, 0),
    };
    try testOp(&opDiv, &test_cases);
}

test "MOD" {
    const test_cases = [_]TestCase{
        // 10 % 3 = 1
        t(10, 3, 1),
        // 10 % 0 = 0 (modulo by zero)
        t(10, 0, 0),
    };
    try testOp(&opMod, &test_cases);
}

test "EXP" {
    const test_cases = [_]TestCase{
        // 2^8 = 256
        t(2, 8, 256),
    };
    try testOp(&opExp, &test_cases);
}

test "SIGNEXTEND" {
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
    try testOp(&opSignextend, &test_cases);
}

test "SDIV" {
    const test_cases = [_]TestCase{
        // 10 / 3 = 3
        t(10, 3, 3),
        // 10 / 0 = 0 (division by zero)
        t(10, 0, 0),
        // MIN_I256 / -1 = MIN_I256 (overflow wraps)
        t(U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } }, U256.MAX, U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } }),
    };
    try testOp(&opSdiv, &test_cases);
}

test "SMOD" {
    const test_cases = [_]TestCase{
        // 10 % 3 = 1
        t(10, 3, 1),
        // 10 % 0 = 0 (modulo by zero)
        t(10, 0, 0),
        // MIN_I256 % -1 = 0 (overflow case)
        t(U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } }, U256.MAX, 0),
    };
    try testOp(&opSmod, &test_cases);
}

test "ADDMOD" {
    const test_cases = [_]TestCase{
        // (5 + 7) % 10 = 2
        TestCase.ternaryCase(5, 7, 10, 2),
        // (5 + 7) % 0 = 0 (modulo by zero)
        TestCase.ternaryCase(5, 7, 0, 0),
    };
    try testOp(&opAddmod, &test_cases);
}

test "MULMOD" {
    const test_cases = [_]TestCase{
        // (5 * 7) % 10 = 5
        TestCase.ternaryCase(5, 7, 10, 5),
        // (5 * 7) % 0 = 0 (modulo by zero)
        TestCase.ternaryCase(5, 7, 0, 0),
    };
    try testOp(&opMulmod, &test_cases);
}
