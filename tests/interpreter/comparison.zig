//! Comparison Operations integration tests

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

test "LT" {
    const test_cases = [_]TestCase{
        .{
            .name = "5 < 10 = true",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x05, // PUSH1 5
                0x10, // LT
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9, // PUSH1(3) + PUSH1(3) + LT(3) + STOP(0)
        },
        .{
            .name = "10 < 5 = false",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5
                0x60, 0x0A, // PUSH1 10
                0x10, // LT
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 9,
        },
        .{
            .name = "5 < 5 = false",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5
                0x60, 0x05, // PUSH1 5
                0x10, // LT
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "GT" {
    const test_cases = [_]TestCase{
        .{
            .name = "10 > 5 = true",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5
                0x60, 0x0A, // PUSH1 10
                0x11, // GT
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9,
        },
        .{
            .name = "5 > 10 = false",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x05, // PUSH1 5
                0x11, // GT
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SLT" {
    const test_cases = [_]TestCase{
        .{
            .name = "5 < 10 = true (both positive)",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10
                0x60, 0x05, // PUSH1 5
                0x12, // SLT
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9,
        },
        .{
            .name = "-1 (all bits set) < 5 = true (negative < positive)",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5 (second operand, pushed first)
                // PUSH32 0xFFFF...FFFF (first operand = -1, on top)
                0x7F, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF, 0xFF,
                0xFF,
                0x12, // SLT -> computes -1 < 5
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9, // PUSH1(3) + PUSH32(3) + SLT(3) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SGT" {
    const test_cases = [_]TestCase{
        .{
            .name = "10 > 5 = true (both positive)",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5
                0x60, 0x0A, // PUSH1 10
                0x13, // SGT
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9,
        },
        .{
            .name = "5 > -1 (all bits set) = true (positive > negative)",
            .bytecode = &[_]u8{
                // PUSH32 0xFFFF...FFFF (second operand = -1, pushed first)
                0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                0x60, 0x05, // PUSH1 5 (first operand, on top)
                0x13, // SGT -> computes 5 > -1
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9, // PUSH32(3) + PUSH1(3) + SGT(3) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "EQ" {
    const test_cases = [_]TestCase{
        .{
            .name = "5 == 5 = true",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5
                0x60, 0x05, // PUSH1 5
                0x14, // EQ
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9,
        },
        .{
            .name = "5 == 10 = false",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5
                0x60, 0x0A, // PUSH1 10
                0x14, // EQ
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 9,
        },
        .{
            .name = "0 == 0 = true",
            .bytecode = &[_]u8{
                0x60, 0x00, // PUSH1 0
                0x60, 0x00, // PUSH1 0
                0x14, // EQ
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 9,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "ISZERO" {
    const test_cases = [_]TestCase{
        .{
            .name = "ISZERO(0) = true",
            .bytecode = &[_]u8{
                0x60, 0x00, // PUSH1 0
                0x15, // ISZERO
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 6, // PUSH1(3) + ISZERO(3) + STOP(0)
        },
        .{
            .name = "ISZERO(1) = false",
            .bytecode = &[_]u8{
                0x60, 0x01, // PUSH1 1
                0x15, // ISZERO
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 6,
        },
        .{
            .name = "ISZERO(255) = false",
            .bytecode = &[_]u8{
                0x60, 0xFF, // PUSH1 255
                0x15, // ISZERO
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 6,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "Combined: complex comparison expressions" {
    const test_cases = [_]TestCase{
        .{
            .name = "(5 < 10) == 1",
            .bytecode = &[_]u8{
                0x60, 0x0A, // PUSH1 10 (second operand)
                0x60, 0x05, // PUSH1 5 (first operand)
                0x10, // LT -> computes 5 < 10, result: [1]
                0x60, 0x01, // PUSH1 1
                0x14, // EQ -> computes 1 == 1, result: [1]
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 15, // PUSH1(3)*3 + LT(3) + EQ(3) + STOP(0)
        },
        .{
            .name = "NOT(5 == 10) using ISZERO",
            .bytecode = &[_]u8{
                0x60, 0x05, // PUSH1 5
                0x60, 0x0A, // PUSH1 10
                0x14, // EQ -> [0] (EQ is commutative, order doesn't matter)
                0x15, // ISZERO -> [1]
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ONE},
            .expected_gas = 12, // PUSH1(3)*2 + EQ(3) + ISZERO(3) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}
