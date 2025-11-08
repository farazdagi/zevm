//! Test helpers for instruction handler tests.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;

const expectEqual = std.testing.expectEqual;

/// Test case for stack operations with varying arity.
pub const TestCase = union(enum) {
    /// Unary operation: 1 operand → 1 result.
    /// Stack: [value, ...] -> [result, ...]
    unary: struct {
        value: U256,
        expected: U256,
    },

    /// Binary operation: 2 operands → 1 result.
    /// Stack: [a, b, ...] -> [result, ...]
    /// where a is first operand (popped first), b is second operand (popped second)
    binary: struct {
        a: U256,
        b: U256,
        expected: U256,
    },

    /// Ternary operation: 3 operands → 1 result.
    /// Stack: [a, b, c, ...] -> [result, ...]
    /// where a is first operand (popped first), b is second, c is third
    ternary: struct {
        a: U256,
        b: U256,
        c: U256,
        expected: U256,
    },

    /// Helper: convert any compatible type to U256.
    inline fn toU256(value: anytype) U256 {
        return switch (@TypeOf(value)) {
            U256 => value,
            u64 => U256.fromU64(value),
            u128 => U256.fromU128(value),
            bool => U256.fromBool(value),
            comptime_int => U256.fromU64(value),
            else => @compileError("Unsupported type for U256 conversion: " ++ @typeName(@TypeOf(value))),
        };
    }

    /// Create a unary test case.
    pub inline fn unaryCase(value: anytype, expected: anytype) @This() {
        return .{ .unary = .{
            .value = toU256(value),
            .expected = toU256(expected),
        } };
    }

    /// Create a binary test case.
    pub inline fn binaryCase(a: anytype, b: anytype, expected: anytype) @This() {
        return .{ .binary = .{
            .a = toU256(a),
            .b = toU256(b),
            .expected = toU256(expected),
        } };
    }

    /// Create a ternary test case.
    pub inline fn ternaryCase(a: anytype, b: anytype, c: anytype, expected: anytype) @This() {
        return .{ .ternary = .{
            .a = toU256(a),
            .b = toU256(b),
            .c = toU256(c),
            .expected = toU256(expected),
        } };
    }
};

/// Universal test helper for stack operations with varying input arity.
/// Operands are pushed to stack in reverse order, so that the first pop
/// gets the first operand of the instruction.
pub fn testOp(
    op_fn: anytype,
    test_cases: []const TestCase,
) !void {
    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        switch (tc) {
            .unary => |case| {
                try stack.push(case.value);
                try op_fn(&stack);

                const result = try stack.pop();
                try std.testing.expect(case.expected.eql(result));
            },
            .binary => |case| {
                try stack.push(case.b); // second operand (pushed first, bottom)
                try stack.push(case.a); // first operand (pushed second, on top)
                try op_fn(&stack);

                const result = try stack.pop();
                try std.testing.expect(case.expected.eql(result));
            },
            .ternary => |case| {
                try stack.push(case.c); // third operand (pushed first, bottom)
                try stack.push(case.b); // second operand
                try stack.push(case.a); // first operand (pushed last, on top)
                try op_fn(&stack);

                const result = try stack.pop();
                try std.testing.expect(case.expected.eql(result));
            },
        }

        try expectEqual(0, stack.len);
    }
}
