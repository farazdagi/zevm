//! Arithmetic Operations integration tests

const std = @import("std");
const zevm = @import("zevm");

const Interpreter = zevm.interpreter.Interpreter;
const ExecutionStatus = zevm.interpreter.ExecutionStatus;
const Spec = zevm.hardfork.Spec;
const U256 = zevm.primitives.U256;

// Test helpers
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "ADD - 2 + 3 = 5" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x02, // PUSH1 2
        0x60, 0x03, // PUSH1 3
        0x01, // ADD
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 5), value.toU64().?);
}

test "ADD - wrapping overflow" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x7F, // PUSH32 U256.MAX
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0x60, 0x01, // PUSH1 1
        0x01, // ADD (should wrap to 0)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expect(value.isZero());
}

test "MUL - 10 * 3 = 30" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x0A, // PUSH1 10
        0x60, 0x03, // PUSH1 3
        0x02, // MUL
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 30), value.toU64().?);
}

test "SUB - 10 - 3 = 7" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x0A, // PUSH1 10
        0x60, 0x03, // PUSH1 3
        0x03, // SUB
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 7), value.toU64().?);
}

test "SUB - wrapping underflow" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x00, // PUSH1 0
        0x60, 0x01, // PUSH1 1
        0x03, // SUB (0 - 1 wraps to MAX)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expect(value.eql(U256.MAX));
}

test "DIV - 10 / 3 = 3" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x0A, // PUSH1 10
        0x60, 0x03, // PUSH1 3
        0x04, // DIV
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 3), value.toU64().?);
}

test "DIV by zero returns 0" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x0A, // PUSH1 10
        0x60, 0x00, // PUSH1 0
        0x04, // DIV (10 / 0 = 0)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expect(value.isZero());
}

test "MOD - 10 % 3 = 1" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x0A, // PUSH1 10
        0x60, 0x03, // PUSH1 3
        0x06, // MOD
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 1), value.toU64().?);
}

test "MOD by zero returns 0" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x0A, // PUSH1 10
        0x60, 0x00, // PUSH1 0
        0x06, // MOD (10 % 0 = 0)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expect(value.isZero());
}

test "Complex arithmetic - (2 + 3) * 4 = 20" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x02, // PUSH1 2
        0x60, 0x03, // PUSH1 3
        0x01, // ADD       -> [5]
        0x60, 0x04, // PUSH1 4   -> [5, 4]
        0x02, // MUL       -> [20]
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 20), value.toU64().?);
}

test "SDIV - signed division" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x0A, // PUSH1 10
        0x60, 0x03, // PUSH1 3
        0x05, // SDIV (10 / 3 = 3)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 3), value.toU64().?);
}

test "SMOD - signed modulo" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x0A, // PUSH1 10
        0x60, 0x03, // PUSH1 3
        0x07, // SMOD (10 % 3 = 1)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 1), value.toU64().?);
}

test "ADDMOD - (5 + 7) % 10 = 2" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x05, // PUSH1 5
        0x60, 0x07, // PUSH1 7
        0x60, 0x0A, // PUSH1 10
        0x08, // ADDMOD
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 2), value.toU64().?);
}

test "MULMOD - (5 * 7) % 10 = 5" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x05, // PUSH1 5
        0x60, 0x07, // PUSH1 7
        0x60, 0x0A, // PUSH1 10
        0x09, // MULMOD
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 5), value.toU64().?);
}

test "EXP - 2^8 = 256" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x02, // PUSH1 2 (base)
        0x60, 0x08, // PUSH1 8 (exponent)
        0x0A, // EXP
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(@as(u64, 256), value.toU64().?);
}

test "Gas consumption - simple arithmetic" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x02, // PUSH1 2    (3 gas)
        0x60, 0x03, // PUSH1 3    (3 gas)
        0x01, // ADD        (3 gas)
        0x00, // STOP       (0 gas)
    };
    // Total: 9 gas

    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(@as(u64, 9), result.gas_used);
}

test "Gas consumption - EXP with dynamic gas" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x02, // PUSH1 2     (3 gas)
        0x60, 0xFF, // PUSH1 255   (3 gas)
        0x0A, // EXP         (10 base + 50*1 byte = 60 gas, post-EIP-160)
        0x00, // STOP        (0 gas)
    };
    // Total: 66 gas

    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(@as(u64, 66), result.gas_used);
}

test "Gas consumption - MUL costs 5 gas" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x0A, // PUSH1 10   (3 gas)
        0x60, 0x03, // PUSH1 3    (3 gas)
        0x02, // MUL        (5 gas)
        0x00, // STOP       (0 gas)
    };
    // Total: 11 gas

    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(@as(u64, 11), result.gas_used);
}

test "Gas consumption - ADDMOD costs 8 gas" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x05, // PUSH1 5    (3 gas)
        0x60, 0x07, // PUSH1 7    (3 gas)
        0x60, 0x0A, // PUSH1 10   (3 gas)
        0x08, // ADDMOD     (8 gas)
        0x00, // STOP       (0 gas)
    };
    // Total: 17 gas

    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(@as(u64, 17), result.gas_used);
}
