//! Test helpers for instruction handler tests.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;

const expectEqual = std.testing.expectEqual;

/// Create a minimal test interpreter with default bytecode (STOP).
pub fn createTestInterpreter() !Interpreter {
    const Spec = @import("../../hardfork.zig").Spec;
    const spec = Spec.forFork(.CANCUN);
    const bytecode = [_]u8{0x00}; // STOP
    return try Interpreter.init(std.testing.allocator, &bytecode, spec, 1000000);
}

/// Create a test interpreter with custom bytecode.
pub fn createTestInterpreterWithBytecode(bytecode: []const u8) !Interpreter {
    const Spec = @import("../../hardfork.zig").Spec;
    const spec = Spec.forFork(.CANCUN);
    return try Interpreter.init(std.testing.allocator, bytecode, spec, 1000000);
}

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
        var interp = try createTestInterpreter();
        defer interp.deinit();

        switch (tc) {
            .unary => |case| {
                try interp.ctx.stack.push(case.value);
                try op_fn(&interp);

                const result = try interp.ctx.stack.pop();
                try std.testing.expect(case.expected.eql(result));
            },
            .binary => |case| {
                try interp.ctx.stack.push(case.b); // second operand (pushed first, bottom)
                try interp.ctx.stack.push(case.a); // first operand (pushed second, on top)
                try op_fn(&interp);

                const result = try interp.ctx.stack.pop();
                try std.testing.expect(case.expected.eql(result));
            },
            .ternary => |case| {
                try interp.ctx.stack.push(case.c); // third operand (pushed first, bottom)
                try interp.ctx.stack.push(case.b); // second operand
                try interp.ctx.stack.push(case.a); // first operand (pushed last, on top)
                try op_fn(&interp);

                const result = try interp.ctx.stack.pop();
                try std.testing.expect(case.expected.eql(result));
            },
        }

        try expectEqual(0, interp.ctx.stack.len);
    }
}
