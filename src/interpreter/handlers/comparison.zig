//! Comparison instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Less than (LT) - unsigned comparison.
///
/// Stack: [a, b, ...] -> [a < b ? 1 : 0, ...]
pub fn opLt(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.set(a.lt(b.*));
}

/// Greater than (GT) - unsigned comparison.
///
/// Stack: [a, b, ...] -> [a > b ? 1 : 0, ...]
pub fn opGt(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.set(a.gt(b.*));
}

/// Signed less than (SLT) - signed comparison.
///
/// Stack: [a, b, ...] -> [a < b ? 1 : 0, ...] (signed)
pub fn opSlt(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.set(a.slt(b.*));
}

/// Signed greater than (SGT) - signed comparison.
///
/// Stack: [a, b, ...] -> [a > b ? 1 : 0, ...] (signed)
pub fn opSgt(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.set(a.sgt(b.*));
}

/// Equality (EQ).
///
/// Stack: [a, b, ...] -> [a == b ? 1 : 0, ...]
pub fn opEq(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.peekMut(0);
    b.set(a.eql(b.*));
}

/// Is zero (ISZERO).
///
/// Stack: [a, ...] -> [a == 0 ? 1 : 0, ...]
pub fn opIszero(interp: *Interpreter) !void {
    const a = try interp.ctx.stack.peekMut(0);
    a.set(a.isZero());
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

test "LT" {
    const test_cases = [_]TestCase{
        t(5, 10, 1),
        t(10, 5, 0),
        t(5, 5, 0),
        t(0, 1, 1),
        t(1, 0, 0),
        t(0, 0, 0),
        t(U256.ZERO, U256.MAX, 1),
        t(U256.MAX, U256.ZERO, 0),
        t(U256.MAX, U256.MAX, 0),
    };

    try testOp(&opLt, &test_cases);
}

test "GT" {
    const test_cases = [_]TestCase{
        t(10, 5, 1),
        t(5, 10, 0),
        t(5, 5, 0),
        t(1, 0, 1),
        t(0, 1, 0),
        t(0, 0, 0),
        t(U256.MAX, U256.ZERO, 1),
        t(U256.ZERO, U256.MAX, 0),
        t(U256.MAX, U256.MAX, 0),
    };

    try testOp(&opGt, &test_cases);
}

test "SLT" {
    const NEG_ONE = U256.MAX;
    const NEG_TWO = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    const MIN_I256 = U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } };

    const test_cases = [_]TestCase{
        t(5, 10, 1),
        t(10, 5, 0),
        t(5, 5, 0),
        t(0, 1, 1),
        t(NEG_ONE, U256.fromU64(5), 1),
        t(U256.fromU64(5), NEG_ONE, 0),
        t(NEG_TWO, NEG_ONE, 1),
        t(NEG_ONE, NEG_TWO, 0),
        t(MIN_I256, U256.ZERO, 1),
    };

    try testOp(&opSlt, &test_cases);
}

test "SGT" {
    const NEG_ONE = U256.MAX;
    const NEG_TWO = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    const MIN_I256 = U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } };

    const test_cases = [_]TestCase{
        t(10, 5, 1),
        t(5, 10, 0),
        t(5, 5, 0),
        t(1, 0, 1),
        t(U256.fromU64(5), NEG_ONE, 1),
        t(NEG_ONE, U256.fromU64(5), 0),
        t(NEG_ONE, NEG_TWO, 1),
        t(NEG_TWO, NEG_ONE, 0),
        t(U256.ZERO, MIN_I256, 1),
    };

    try testOp(&opSgt, &test_cases);
}

test "EQ" {
    const test_cases = [_]TestCase{
        t(5, 5, 1),
        t(5, 10, 0),
        t(0, 0, 1),
        t(0, 1, 0),
        t(1000, 1000, 1),
        t(U256.MAX, U256.MAX, 1),
        t(U256.MAX, U256.ZERO, 0),
        t(U256.ZERO, U256.MAX, 0),
    };

    try testOp(&opEq, &test_cases);
}

test "ISZERO" {
    const test_cases = [_]TestCase{
        tu(0, 1),
        tu(1, 0),
        tu(5, 0),
        tu(255, 0),
        tu(U256.MAX, 0),
    };

    try testOp(&opIszero, &test_cases);
}
