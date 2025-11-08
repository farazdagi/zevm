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
    try expectEqual(5, value.toU64().?);
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
    try expectEqual(30, value.toU64().?);
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
    try expectEqual(7, value.toU64().?);
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
    try expectEqual(3, value.toU64().?);
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
    try expectEqual(1, value.toU64().?);
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
    try expectEqual(20, value.toU64().?);
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
    try expectEqual(3, value.toU64().?);
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
    try expectEqual(1, value.toU64().?);
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
    try expectEqual(2, value.toU64().?);
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
    try expectEqual(5, value.toU64().?);
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
    try expectEqual(256, value.toU64().?);
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
    try expectEqual(9, result.gas_used);
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
    try expectEqual(66, result.gas_used);
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
    try expectEqual(11, result.gas_used);
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
    try expectEqual(17, result.gas_used);
}

test "SIGNEXTEND" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const test_cases = [_]struct {
        name: []const u8,
        bytecode: []const u8,
        expected_stack: []const U256,
    }{
        .{
            .name = "byte 0 positive (0x7F)",
            .bytecode = &[_]u8{
                0x60, 0x7F, // PUSH1 0x7F (value with bit 7 = 0)
                0x60, 0x00, // PUSH1 0 (byte_num)
                0x0B, // SIGNEXTEND
                0x00, // STOP
            },
            // Should remain 0x7F
            .expected_stack = &[_]U256{U256.fromU64(0x7F)},
        },
        .{
            .name = "byte 0 negative (0xFF)",
            .bytecode = &[_]u8{
                0x60, 0xFF, // PUSH1 0xFF (value with bit 7 = 1)
                0x60, 0x00, // PUSH1 0 (byte_num)
                0x0B, // SIGNEXTEND
                0x00, // STOP
            },
            // Should extend to all 1s
            .expected_stack = &[_]U256{U256.MAX},
        },
        .{
            .name = "byte 1 positive (0x7FFF)",
            .bytecode = &[_]u8{
                0x61, 0x7F, 0xFF, // PUSH2 0x7FFF (bit 15 = 0)
                0x60, 0x01, // PUSH1 1 (byte_num)
                0x0B, // SIGNEXTEND
                0x00, // STOP
            },
            // Should remain 0x7FFF
            .expected_stack = &[_]U256{U256.fromU64(0x7FFF)},
        },
        .{
            .name = "byte 1 negative (0x8FFF)",
            .bytecode = &[_]u8{
                0x61, 0x8F, 0xFF, // PUSH2 0x8FFF (bit 15 = 1)
                0x60, 0x01, // PUSH1 1 (byte_num)
                0x0B, // SIGNEXTEND
                0x00, // STOP
            },
            // Should extend bit 15 to all higher bits (including limbs 1-3)
            .expected_stack = &[_]U256{U256{ .limbs = .{
                0xFFFF_FFFF_FFFF_8FFF,
                0xFFFF_FFFF_FFFF_FFFF,
                0xFFFF_FFFF_FFFF_FFFF,
                0xFFFF_FFFF_FFFF_FFFF,
            } }},
        },
        .{
            .name = "byte 31 (no change)",
            .bytecode = &[_]u8{
                0x64, 0x12, 0x34, 0x56, 0x78, 0x90, // PUSH5 0x1234567890
                0x60, 0x1F, // PUSH1 31 (byte_num)
                0x0B, // SIGNEXTEND
                0x00, // STOP
            },
            // Should remain unchanged
            .expected_stack = &[_]U256{U256.fromU64(0x1234567890)},
        },
        .{
            .name = "byte_num > 31 (no change)",
            .bytecode = &[_]u8{
                0x64, 0x12, 0x34, 0x56, 0x78, 0x90, // PUSH5 0x1234567890
                0x60, 0x64, // PUSH1 100 (byte_num > 31)
                0x0B, // SIGNEXTEND
                0x00, // STOP
            },
            // Should remain unchanged
            .expected_stack = &[_]U256{U256.fromU64(0x1234567890)},
        },
        .{
            .name = "clearing high bits",
            .bytecode = &[_]u8{
                0x63, 0xFF, 0xFF, 0xFF, 0x7F, // PUSH4 0xFFFFFF7F
                0x60, 0x00, // PUSH1 0 (byte_num)
                0x0B, // SIGNEXTEND
                0x00, // STOP
            },
            // Bit 7 of byte 0 is 0 (0x7F), so should clear all higher bits
            .expected_stack = &[_]U256{U256.fromU64(0x7F)},
        },
    };

    for (test_cases) |tc| {
        var interpreter = try Interpreter.init(allocator, tc.bytecode, spec, 10000);
        defer interpreter.deinit();

        const result = try interpreter.run();
        try expectEqual(ExecutionStatus.SUCCESS, result.status);

        // Build expected stack for comparison
        var expected_stack = try zevm.interpreter.Stack.init(allocator);
        defer expected_stack.deinit();
        for (tc.expected_stack) |value| {
            try expected_stack.push(value);
        }

        try expect(interpreter.stack.eql(&expected_stack));
    }
}

test "SIGNEXTEND - gas consumption" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0xFF, // PUSH1 0xFF (3 gas)
        0x60, 0x00, // PUSH1 0    (3 gas)
        0x0B, // SIGNEXTEND (5 gas - VERYLOW)
        0x00, // STOP       (0 gas)
    };
    // Total: 11 gas

    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(11, result.gas_used);
}
