//! Control flow instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;
const Memory = @import("../memory.zig").Memory;
const AnalyzedBytecode = @import("../bytecode.zig").AnalyzedBytecode;
const Gas = @import("../gas/mod.zig").Gas;

/// Jump to destination (JUMP).
///
/// Stack: [counter, ...] -> [...]
/// Unconditionally jumps to the specified counter if it's a valid JUMPDEST.
/// Returns the new PC value, which the interpreter must set.
pub inline fn opJump(stack: *Stack, bytecode: *const AnalyzedBytecode) !usize {
    const counter_u256 = try stack.pop();

    // Convert to usize, checking for overflow.
    const counter = counter_u256.toUsize() orelse return error.InvalidJump;

    // Validate destination.
    if (!bytecode.isValidJump(counter)) {
        return error.InvalidJump;
    }

    return counter;
}

/// Conditional jump (JUMPI).
///
/// Stack: [counter, b, ...] -> [...]
/// Jumps to counter if b != 0, otherwise continues to next instruction.
/// Returns the new PC value if jumping (b != 0), or null if not jumping (b == 0).
pub inline fn opJumpi(stack: *Stack, bytecode: *const AnalyzedBytecode) !?usize {
    const counter_u256 = try stack.pop();
    const b = try stack.pop();

    // If condition is zero, don't jump (return null).
    if (b.isZero()) {
        return null;
    }

    // Convert to usize, checking for overflow.
    const counter = counter_u256.toUsize() orelse return error.InvalidJump;

    // Validate destination
    if (!bytecode.isValidJump(counter)) {
        return error.InvalidJump;
    }

    return counter;
}

/// Get program counter (PC).
///
/// Stack: [...] -> [..., pc]
/// Returns the current value of the program counter (the position of this PC instruction).
pub inline fn opPc(stack: *Stack, pc: usize) !void {
    try stack.push(U256.fromU64(@intCast(pc)));
}

/// Get remaining gas (GAS).
///
/// Stack: [...] -> [..., gas]
/// Returns the amount of available gas after this instruction.
/// The gas value pushed is AFTER charging the base cost of the GAS opcode itself.
pub inline fn opGas(stack: *Stack, gas: *const Gas) !void {
    const remaining = gas.remaining();
    try stack.push(U256.fromU64(remaining));
}

/// Halt execution and return data (RETURN).
///
/// Stack: [offset, size, ...] -> []
/// Halts execution and returns data from memory.
/// Returns a slice of memory that the interpreter must copy and store.
/// Gas is charged by the interpreter before calling this handler.
pub inline fn opReturn(stack: *Stack, memory: *Memory) ![]const u8 {
    const offset_u256 = try stack.pop();
    const size_u256 = try stack.pop();

    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const size = size_u256.toUsize() orelse return error.InvalidOffset;

    // Handle empty return data case
    if (size == 0) {
        return &[_]u8{};
    }

    // Expand memory if needed
    try memory.ensureCapacity(offset, size);

    // Get output data from memory
    return try memory.getSlice(offset, size);
}

/// Halt execution and revert state changes (REVERT).
///
/// Stack: [offset, size, ...] -> []
/// Halts execution, reverts state, and returns error data from memory.
/// Returns a slice of memory that the interpreter must copy and store.
/// Available from Byzantium (EIP-140) onwards.
/// Gas is charged by the interpreter before calling this handler.
pub inline fn opRevert(stack: *Stack, memory: *Memory) ![]const u8 {
    const offset_u256 = try stack.pop();
    const size_u256 = try stack.pop();

    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const size = size_u256.toUsize() orelse return error.InvalidOffset;

    // Handle empty revert data case
    if (size == 0) {
        return &[_]u8{};
    }

    // Expand memory if needed
    try memory.ensureCapacity(offset, size);

    // Get output data from memory
    return try memory.getSlice(offset, size);
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "PC" {
    const test_cases = [_]struct {
        pc: usize,
        expected: u64,
    }{
        .{ .pc = 0, .expected = 0 },
        .{ .pc = 10, .expected = 10 },
        .{ .pc = 255, .expected = 255 },
        .{ .pc = 1000, .expected = 1000 },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        try opPc(&stack, tc.pc);

        const result = try stack.pop();
        try expectEqual(tc.expected, result.toU64().?);
    }
}

test "GAS" {
    const Spec = @import("../../hardfork.zig").Spec;
    const test_cases = [_]struct {
        gas_limit: u64,
        gas_used: u64,
        expected: u64,
    }{
        .{ .gas_limit = 100, .gas_used = 30, .expected = 70 },
        .{ .gas_limit = 1000000, .gas_used = 500000, .expected = 500000 },
        .{ .gas_limit = 50, .gas_used = 50, .expected = 0 },
    };

    const spec = Spec.forFork(.CANCUN);
    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var gas = Gas.init(tc.gas_limit, spec);
        try gas.consume(tc.gas_used);

        try opGas(&stack, &gas);

        const result = try stack.pop();
        try expectEqual(tc.expected, result.toU64().?);
    }
}

test "JUMP" {
    const TestCase = struct {
        name: []const u8,
        bytecode: []const u8,
        destination: u64,
        expected: union(enum) {
            success: usize,
            err: anyerror,
        },
    };

    const test_cases = [_]TestCase{
        .{
            .name = "valid jump to JUMPDEST",
            .bytecode = &[_]u8{ 0x5B, 0x00 },
            .destination = 0,
            .expected = .{ .success = 0 },
        },
        .{
            .name = "invalid destination (not JUMPDEST)",
            .bytecode = &[_]u8{ 0x00, 0x5B },
            .destination = 0,
            .expected = .{ .err = error.InvalidJump },
        },
        .{
            .name = "out of bounds",
            .bytecode = &[_]u8{0x5B},
            .destination = 100,
            .expected = .{ .err = error.InvalidJump },
        },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var bytecode = try AnalyzedBytecode.analyze(std.testing.allocator, tc.bytecode);
        defer bytecode.deinit();

        try stack.push(U256.fromU64(tc.destination));

        switch (tc.expected) {
            .success => |expected_pc| {
                const new_pc = try opJump(&stack, &bytecode);
                try expectEqual(expected_pc, new_pc);
                try expectEqual(@as(usize, 0), stack.len); // Stack should be empty after pop
            },
            .err => |expected_err| {
                try expectError(expected_err, opJump(&stack, &bytecode));
            },
        }
    }
}

test "JUMPI" {
    const TestCase = struct {
        name: []const u8,
        bytecode: []const u8,
        condition: u64,
        destination: u64,
        expected: union(enum) {
            success: ?usize,
            err: anyerror,
        },
    };

    const test_cases = [_]TestCase{
        .{
            .name = "condition true, valid jump",
            .bytecode = &[_]u8{0x5B}, // JUMPDEST
            .condition = 1,
            .destination = 0,
            .expected = .{ .success = 0 },
        },
        .{
            .name = "condition false, no jump",
            .bytecode = &[_]u8{0x5B}, // JUMPDEST
            .condition = 0,
            .destination = 0,
            .expected = .{ .success = null },
        },
        .{
            .name = "condition true, invalid destination (not JUMPDEST)",
            .bytecode = &[_]u8{ 0x00, 0x5B }, // STOP, JUMPDEST
            .condition = 1,
            .destination = 0,
            .expected = .{ .err = error.InvalidJump },
        },
        .{
            .name = "condition true, out of bounds",
            .bytecode = &[_]u8{0x5B}, // JUMPDEST
            .condition = 1,
            .destination = 100,
            .expected = .{ .err = error.InvalidJump },
        },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var bytecode = try AnalyzedBytecode.analyze(std.testing.allocator, tc.bytecode);
        defer bytecode.deinit();

        try stack.push(U256.fromU64(tc.condition));
        try stack.push(U256.fromU64(tc.destination));

        switch (tc.expected) {
            .success => |expected_pc| {
                const new_pc = try opJumpi(&stack, &bytecode);
                if (expected_pc) |expected| {
                    try expect(new_pc != null);
                    try expectEqual(expected, new_pc.?);
                } else {
                    try expect(new_pc == null);
                }
                try expectEqual(@as(usize, 0), stack.len); // Stack should be empty after both pops
            },
            .err => |expected_err| {
                try expectError(expected_err, opJumpi(&stack, &bytecode));
            },
        }
    }
}
