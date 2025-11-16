//! Test helpers for instruction handler tests.

const std = @import("std");
const Allocator = std.mem.Allocator;
const U256 = @import("../../primitives/big.zig").U256;
const Address = @import("../../primitives/address.zig").Address;
const Interpreter = @import("../interpreter.zig").Interpreter;
const Env = @import("../../context.zig").Env;
const MockHost = @import("../../host/mock.zig").MockHost;
const Spec = @import("../../hardfork.zig").Spec;

const expectEqual = std.testing.expectEqual;

/// This ensures that pointers within the interpreter remain valid.
pub const TestContext = struct {
    env: Env,
    mock: MockHost,
    interp: Interpreter,
    allocator: Allocator,

    /// Create test context with default bytecode (STOP) and default contract address (zero).
    pub fn create(allocator: Allocator) !*TestContext {
        return createWithBytecode(allocator, &[_]u8{0x00}, Address.zero());
    }

    /// Create test context with custom bytecode and contract address.
    pub fn createWithBytecode(allocator: Allocator, bytecode: []const u8, contract_address: Address) !*TestContext {
        const self = try allocator.create(TestContext);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.env = Env.default();
        self.mock = MockHost.init(allocator);
        errdefer self.mock.deinit();

        self.interp = try Interpreter.init(
            allocator,
            bytecode,
            contract_address,
            Spec.forFork(.CANCUN),
            1000000,
            &self.env,
            self.mock.host(),
        );

        return self;
    }

    /// Clean up all resources and free the context.
    pub fn destroy(self: *TestContext) void {
        self.interp.deinit();
        self.mock.deinit();
        self.allocator.destroy(self);
    }
};

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
        var ctx = try TestContext.create(std.testing.allocator);
        defer ctx.destroy();

        switch (tc) {
            .unary => |case| {
                try ctx.interp.ctx.stack.push(case.value);
                try op_fn(&ctx.interp);

                const result = try ctx.interp.ctx.stack.pop();
                try std.testing.expect(case.expected.eql(result));
            },
            .binary => |case| {
                try ctx.interp.ctx.stack.push(case.b); // second operand (pushed first, bottom)
                try ctx.interp.ctx.stack.push(case.a); // first operand (pushed second, on top)
                try op_fn(&ctx.interp);

                const result = try ctx.interp.ctx.stack.pop();
                try std.testing.expect(case.expected.eql(result));
            },
            .ternary => |case| {
                try ctx.interp.ctx.stack.push(case.c); // third operand (pushed first, bottom)
                try ctx.interp.ctx.stack.push(case.b); // second operand
                try ctx.interp.ctx.stack.push(case.a); // first operand (pushed last, on top)
                try op_fn(&ctx.interp);

                const result = try ctx.interp.ctx.stack.pop();
                try std.testing.expect(case.expected.eql(result));
            },
        }

        try expectEqual(0, ctx.interp.ctx.stack.len);
    }
}
