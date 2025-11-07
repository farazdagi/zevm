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
/// Extends the sign bit from position (byte_num * 8 + 7)
pub inline fn signextend(stack: *Stack) !void {
    _ = stack;
    return error.UnimplementedOpcode;
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

test "signextend: unimplemented" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(0xFF));
    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, signextend(&stack));
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
