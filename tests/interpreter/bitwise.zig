//! Bitwise Operations integration tests

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

test "AND" {
    const test_cases = [_]TestCase{
        .{
            .name = "0xFF & 0xAA = 0xAA",
            .bytecode = &[_]u8{
                0x60, 0xFF, // PUSH1 0xFF
                0x60, 0xAA, // PUSH1 0xAA
                0x16, // AND
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(0xAA)},
            .expected_gas = 9, // PUSH1(3) + PUSH1(3) + AND(3) + STOP(0)
        },
        .{
            .name = "0xF0 & 0x0F = 0x00",
            .bytecode = &[_]u8{
                0x60, 0xF0, // PUSH1 0xF0
                0x60, 0x0F, // PUSH1 0x0F
                0x16, // AND
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "OR" {
    const test_cases = [_]TestCase{
        .{
            .name = "0xF0 | 0x0F = 0xFF",
            .bytecode = &[_]u8{
                0x60, 0xF0, // PUSH1 0xF0
                0x60, 0x0F, // PUSH1 0x0F
                0x17, // OR
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(0xFF)},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "XOR" {
    const test_cases = [_]TestCase{
        .{
            .name = "0xFF ^ 0xAA = 0x55",
            .bytecode = &[_]u8{
                0x60, 0xFF, // PUSH1 0xFF
                0x60, 0xAA, // PUSH1 0xAA
                0x18, // XOR
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(0x55)},
            .expected_gas = 9,
        },
        .{
            .name = "x ^ x = 0 (identity)",
            .bytecode = &[_]u8{
                0x60, 0xAA, // PUSH1 0xAA
                0x60, 0xAA, // PUSH1 0xAA
                0x18, // XOR
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "NOT" {
    const test_cases = [_]TestCase{
        .{
            .name = "~0xFF = 0xFFFF...FF00",
            .bytecode = &[_]u8{
                0x60, 0xFF, // PUSH1 0xFF
                0x19, // NOT
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256{
                .limbs = .{
                    0xFFFFFFFFFFFFFF00,
                    0xFFFFFFFFFFFFFFFF,
                    0xFFFFFFFFFFFFFFFF,
                    0xFFFFFFFFFFFFFFFF,
                },
            }},
            .expected_gas = 6, // PUSH1(3) + NOT(3) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "BYTE" {
    const test_cases = [_]TestCase{
        .{
            .name = "Extract byte 0 from 0x0102030405...",
            .bytecode = &[_]u8{
                // PUSH2 0x0102
                0x61, 0x01, 0x02,
                0x60, 0x00, // PUSH1 0 (byte index - most significant)
                0x1A, // BYTE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO}, // Byte 0 of 0x0102 (padded) is 0x00
            .expected_gas = 9, // PUSH2(3) + PUSH1(3) + BYTE(3) + STOP(0)
        },
        .{
            .name = "Extract byte 30 from 0x0102",
            .bytecode = &[_]u8{
                // PUSH2 0x0102
                0x61, 0x01, 0x02,
                0x60, 0x1E, // PUSH1 30 (byte index)
                0x1A, // BYTE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(0x01)}, // Byte 30 = 0x01
            .expected_gas = 9,
        },
        .{
            .name = "Extract byte 31 from 0x0102",
            .bytecode = &[_]u8{
                // PUSH2 0x0102
                0x61, 0x01, 0x02,
                0x60, 0x1F, // PUSH1 31 (byte index - least significant)
                0x1A, // BYTE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(0x02)}, // Byte 31 = 0x02
            .expected_gas = 9,
        },
        .{
            .name = "Extract byte 32 (out of bounds)",
            .bytecode = &[_]u8{
                // PUSH2 0x0102
                0x61, 0x01, 0x02,
                0x60, 0x20, // PUSH1 32 (out of bounds)
                0x1A, // BYTE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO}, // Out of bounds = 0
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SHL" {
    const test_cases = [_]TestCase{
        .{
            .name = "1 << 8 = 256",
            .bytecode = &[_]u8{
                0x60, 0x01, // PUSH1 1
                0x60, 0x08, // PUSH1 8 (shift amount)
                0x1B, // SHL
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(256)},
            .expected_gas = 9,
        },
        .{
            .name = "0xFF << 4 = 0xFF0",
            .bytecode = &[_]u8{
                0x60, 0xFF, // PUSH1 0xFF
                0x60, 0x04, // PUSH1 4
                0x1B, // SHL
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(0xFF0)},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SHR" {
    const test_cases = [_]TestCase{
        .{
            .name = "256 >> 8 = 1",
            .bytecode = &[_]u8{
                0x61, 0x01, 0x00, // PUSH2 0x0100 (256)
                0x60, 0x08, // PUSH1 8 (shift amount)
                0x1C, // SHR
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9, // PUSH2(3) + PUSH1(3) + SHR(3) + STOP(0)
        },
        .{
            .name = "0xFF00 >> 8 = 0xFF",
            .bytecode = &[_]u8{
                0x61, 0xFF, 0x00, // PUSH2 0xFF00
                0x60, 0x08, // PUSH1 8
                0x1C, // SHR
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(0xFF)},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SAR" {
    const test_cases = [_]TestCase{
        .{
            .name = "256 SAR 8 = 1 (positive, same as SHR)",
            .bytecode = &[_]u8{
                0x61, 0x01, 0x00, // PUSH2 0x0100 (256)
                0x60, 0x08, // PUSH1 8
                0x1D, // SAR
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "Combined: bit manipulations" {
    const test_cases = [_]TestCase{
        .{
            .name = "(0xAA AND 0xFF) OR 0x55 = 0xFF",
            .bytecode = &[_]u8{
                0x60, 0xAA, // PUSH1 0xAA
                0x60, 0xFF, // PUSH1 0xFF
                0x16, // AND -> [0xAA]
                0x60, 0x55, // PUSH1 0x55
                0x17, // OR -> [0xFF]
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(0xFF)},
            .expected_gas = 15, // PUSH1(3)*3 + AND(3) + OR(3) + STOP(0)
        },
        .{
            .name = "(1 << 8) >> 8 = 1",
            .bytecode = &[_]u8{
                0x60, 0x01, // PUSH1 1
                0x60, 0x08, // PUSH1 8
                0x1B, // SHL -> [256]
                0x60, 0x08, // PUSH1 8
                0x1C, // SHR -> [1]
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 15,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}
