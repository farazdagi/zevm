//! Arithmetic Operations integration tests

const std = @import("std");
const zevm = @import("zevm");
const test_helpers = @import("test_helpers.zig");

const Interpreter = zevm.interpreter.Interpreter;
const ExecutionStatus = zevm.interpreter.ExecutionStatus;
const Spec = zevm.hardfork.Spec;
const U256 = zevm.primitives.U256;
const TestCase = test_helpers.TestCase;
const runOpcodeTests = test_helpers.runOpcodeTests;

// Test helpers
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "ADD" {
    const test_cases = [_]TestCase{
        .{
            .name = "2 + 3 = 5",
            .bytecode = &[_]u8{
                0x60, 0x02, // PUSH1 2
                0x60, 0x03, // PUSH1 3
                0x01, // ADD
                0x00, // STOP
            },
            // Stack: [5]
            .expected_stack = &[_]U256{U256.fromU64(5)},
            .expected_gas = 9, // PUSH1(3) + PUSH1(3) + ADD(3) + STOP(0)
        },
        .{
            .name = "wrapping overflow (MAX + 1 = 0)",
            .bytecode = &[_]u8{
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
                0x01, // ADD (wraps to 0)
                0x00, // STOP
            },
            // Stack: [0] (U256.MAX + 1 wraps to 0)
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 9, // PUSH32(3) + PUSH1(3) + ADD(3) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "MUL" {
    const test_cases = [_]TestCase{
        .{
            .name = "10 * 3 = 30",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x03, // PUSH1 3
                0x02, // MUL
                0x00, // STOP
            },
            // Stack: [30]
            .expected_stack = &[_]U256{U256.fromU64(30)},
            .expected_gas = 11, // PUSH1(3) + PUSH1(3) + MUL(5) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SUB" {
    const test_cases = [_]TestCase{
        .{
            .name = "10 - 3 = 7",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x03, // PUSH1 3
                0x03, // SUB
                0x00, // STOP
            },
            // Stack: [7]
            .expected_stack = &[_]U256{U256.fromU64(7)},
            .expected_gas = 9, // PUSH1(3) + PUSH1(3) + SUB(3) + STOP(0)
        },
        .{
            .name = "wrapping underflow (0 - 1 = MAX)",
            .bytecode = &[_]u8{
                0x60, 0x00, // PUSH1 0
                0x60, 0x01, // PUSH1 1
                0x03, // SUB (wraps to MAX)
                0x00, // STOP
            },
            // Stack: [U256.MAX] (0 - 1 wraps to MAX)
            .expected_stack = &[_]U256{U256.MAX},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "DIV" {
    const test_cases = [_]TestCase{
        .{
            .name = "10 / 3 = 3",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x03, // PUSH1 3
                0x04, // DIV
                0x00, // STOP
            },
            // Stack: [3] (integer division)
            .expected_stack = &[_]U256{U256.fromU64(3)},
            .expected_gas = 11, // PUSH1(3) + PUSH1(3) + DIV(5) + STOP(0)
        },
        .{
            .name = "division by zero returns 0",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x00, // PUSH1 0
                0x04, // DIV (10 / 0 = 0)
                0x00, // STOP
            },
            // Stack: [0] (10 / 0 = 0 per EVM spec)
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 11,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "MOD" {
    const test_cases = [_]TestCase{
        .{
            .name = "10 % 3 = 1",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x03, // PUSH1 3
                0x06, // MOD
                0x00, // STOP
            },
            // Stack: [1]
            .expected_stack = &[_]U256{U256.fromU64(1)},
            .expected_gas = 11, // PUSH1(3) + PUSH1(3) + MOD(5) + STOP(0)
        },
        .{
            .name = "modulo by zero returns 0",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x00, // PUSH1 0
                0x06, // MOD (10 % 0 = 0)
                0x00, // STOP
            },
            // Stack: [0] (10 % 0 = 0 per EVM spec)
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 11,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "Complex arithmetic" {
    const test_cases = [_]TestCase{
        .{
            .name = "(2 + 3) * 4 = 20",
            .bytecode = &[_]u8{
                0x60, 0x02, // PUSH1 2
                0x60, 0x03, // PUSH1 3
                0x01, // ADD       -> [5]
                0x60, 0x04, // PUSH1 4   -> [5, 4]
                0x02, // MUL       -> [20]
                0x00, // STOP
            },
            // Stack: [20] (evaluates as (2+3)*4)
            .expected_stack = &[_]U256{U256.fromU64(20)},
            .expected_gas = 17, // PUSH1(3) + PUSH1(3) + ADD(3) + PUSH1(3) + MUL(5) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SDIV" {
    const test_cases = [_]TestCase{
        .{
            .name = "signed division 10 / 3 = 3",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x03, // PUSH1 3
                0x05, // SDIV
                0x00, // STOP
            },
            // Stack: [3] (signed integers, both positive)
            .expected_stack = &[_]U256{U256.fromU64(3)},
            .expected_gas = 11, // PUSH1(3) + PUSH1(3) + SDIV(5) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SMOD" {
    const test_cases = [_]TestCase{
        .{
            .name = "signed modulo 10 % 3 = 1",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x03, // PUSH1 3
                0x07, // SMOD
                0x00, // STOP
            },
            // Stack: [1] (signed integers, both positive)
            .expected_stack = &[_]U256{U256.fromU64(1)},
            .expected_gas = 11, // PUSH1(3) + PUSH1(3) + SMOD(5) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "ADDMOD" {
    const test_cases = [_]TestCase{
        .{
            .name = "(5 + 7) % 10 = 2",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5
                0x60, 0x07, // PUSH1 7
                0x60, 0x0A, // PUSH1 10
                0x08, // ADDMOD
                0x00, // STOP
            },
            // Stack: [2] ((5 + 7) mod 10 = 12 mod 10 = 2)
            .expected_stack = &[_]U256{U256.fromU64(2)},
            .expected_gas = 17, // PUSH1(3) + PUSH1(3) + PUSH1(3) + ADDMOD(8) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "MULMOD" {
    const test_cases = [_]TestCase{
        .{
            .name = "(5 * 7) % 10 = 5",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5
                0x60, 0x07, // PUSH1 7
                0x60, 0x0A, // PUSH1 10
                0x09, // MULMOD
                0x00, // STOP
            },
            // Stack: [5] ((5 * 7) mod 10 = 35 mod 10 = 5)
            .expected_stack = &[_]U256{U256.fromU64(5)},
            .expected_gas = 17, // PUSH1(3) + PUSH1(3) + PUSH1(3) + MULMOD(8) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "EXP" {
    const test_cases = [_]TestCase{
        .{
            .name = "2^8 = 256",
            .bytecode = &[_]u8{
                0x60, 0x02, // PUSH1 2 (base)
                0x60, 0x08, // PUSH1 8 (exponent)
                0x0A, // EXP
                0x00, // STOP
            },
            // Stack: [256] (2 to the power of 8)
            .expected_stack = &[_]U256{U256.fromU64(256)},
            .expected_gas = 66, // PUSH1(3) + PUSH1(3) + EXP(10 base + 50*1 byte) + STOP(0)
        },
        .{
            .name = "2^255 with dynamic gas",
            .bytecode = &[_]u8{
                0x60, 0x02, // PUSH1 2
                0x60, 0xFF, // PUSH1 255
                0x0A, // EXP
                0x00, // STOP
            },
            // Stack: [2^255] (large exponent triggers dynamic gas)
            .expected_stack = &[_]U256{
                U256{ .limbs = .{
                    0x0000000000000000,
                    0x0000000000000000,
                    0x0000000000000000,
                    0x8000000000000000,
                } },
            },
            .expected_gas = 66, // PUSH1(3) + PUSH1(3) + EXP(10 + 50*1 byte) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SIGNEXTEND" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const test_cases = [_]struct {
        name: []const u8,
        bytecode: []const u8,
        expected_stack: []const U256,
        expected_gas: u64,
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
            .expected_gas = 11, // PUSH1(3) + PUSH1(3) + SIGNEXTEND(5) + STOP(0)
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
            .expected_gas = 11,
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
            .expected_gas = 11, // PUSH2(3) + PUSH1(3) + SIGNEXTEND(5) + STOP(0)
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
            .expected_gas = 11,
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
            .expected_gas = 11, // PUSH5(3) + PUSH1(3) + SIGNEXTEND(5) + STOP(0)
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
            .expected_gas = 11,
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
            .expected_gas = 11, // PUSH4(3) + PUSH1(3) + SIGNEXTEND(5) + STOP(0)
        },
    };

    for (test_cases) |tc| {
        var interpreter = try Interpreter.init(allocator, tc.bytecode, spec, 10000);
        defer interpreter.deinit();

        const result = try interpreter.run();
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        try expectEqual(tc.expected_gas, result.gas_used);

        // Build expected stack for comparison
        var expected_stack = try zevm.interpreter.Stack.init(allocator);
        defer expected_stack.deinit();
        for (tc.expected_stack) |value| {
            try expected_stack.push(value);
        }

        try expect(interpreter.stack.eql(&expected_stack));
    }
}
