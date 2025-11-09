//! Memory Operations integration tests

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

test "MLOAD: load from empty memory" {
    const test_cases = [_]TestCase{
        .{
            .name = "MLOAD offset 0 from empty memory returns zero",
            .bytecode = &[_]u8{
                0x60, 0x00, // PUSH1 0 (offset)
                0x51, // MLOAD
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            // PUSH1(3) + MLOAD(3 base + 3 expansion) + STOP(0) = 9
            .expected_gas = 9,
        },
        .{
            .name = "MLOAD offset 32 expands memory to 64 bytes",
            .bytecode = &[_]u8{
                0x60, 0x20, // PUSH1 32 (offset)
                0x51, // MLOAD
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            // PUSH1(3) + MLOAD(3 base + 6 expansion) + STOP(0) = 12
            // Expansion: memoryCost(64) - memoryCost(0) = 6 - 0 = 6
            .expected_gas = 12,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "MSTORE: store word to memory" {
    const test_cases = [_]TestCase{
        .{
            .name = "MSTORE at offset 0",
            .bytecode = &[_]u8{
                0x60, 0x42, // PUSH1 0x42 (value)
                0x60, 0x00, // PUSH1 0 (offset)
                0x52, // MSTORE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{},
            // PUSH1(3) + PUSH1(3) + MSTORE(3 base + 3 expansion) + STOP(0) = 12
            .expected_gas = 12,
        },
        .{
            .name = "MSTORE then MLOAD verifies value",
            .bytecode = &[_]u8{
                0x61, 0x12, 0x34, // PUSH2 0x1234 (value)
                0x60, 0x00, // PUSH1 0 (offset)
                0x52, // MSTORE
                0x60, 0x00, // PUSH1 0 (offset for MLOAD)
                0x51, // MLOAD
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(0x1234)},
            // PUSH2(3) + PUSH1(3) + MSTORE(3+3) + PUSH1(3) + MLOAD(3+0) + STOP(0) = 18
            .expected_gas = 18,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "MSTORE: multiple expansions" {
    const test_cases = [_]TestCase{
        .{
            .name = "MSTORE at offset 0 then offset 64",
            .bytecode = &[_]u8{
                0x60, 0x42, // PUSH1 0x42
                0x60, 0x00, // PUSH1 0 (first offset)
                0x52, // MSTORE (expands to 32 bytes)
                0x60, 0x99, // PUSH1 0x99
                0x60, 0x40, // PUSH1 64 (second offset)
                0x52, // MSTORE (expands to 96 bytes)
                0x00, // STOP
            },
            .expected_stack = &[_]U256{},
            // PUSH1(3) + PUSH1(3) + MSTORE(3+3) + PUSH1(3) + PUSH1(3) + MSTORE(3+3) + STOP(0) = 24
            // Second MSTORE expansion: memoryCost(96) - memoryCost(32) = 9 - 3 = 6, but wait...
            // Actually: memoryCost(96) = (3*3) + (3*3)/512 = 9 + 0 = 9
            // memoryCost(32) = (1*3) + (1*1)/512 = 3 + 0 = 3
            // Expansion = 9 - 3 = 6, so second MSTORE costs 3 + 6 = 9
            // Total: 3 + 3 + 6 + 3 + 3 + 9 + 0 = 27
            .expected_gas = 27,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "MSTORE8: store byte to memory" {
    const test_cases = [_]TestCase{
        .{
            .name = "MSTORE8 stores only LSB",
            .bytecode = &[_]u8{
                0x61, 0x12, 0x34, // PUSH2 0x1234 (value)
                0x60, 0x00, // PUSH1 0 (offset)
                0x53, // MSTORE8 (stores 0x34)
                0x60, 0x00, // PUSH1 0
                0x51, // MLOAD
                0x00, // STOP
            },
            .expected_stack = &[_]U256{
                // Byte 0 should be 0x34, rest zeros
                // In big-endian: 0x3400...000
                U256.fromU64(0x34).shl(248), // Shift to MSB position
            },
            // PUSH2(3) + PUSH1(3) + MSTORE8(3+3) + PUSH1(3) + MLOAD(3+0) + STOP(0) = 18
            .expected_gas = 18,
        },
        .{
            .name = "MSTORE8 at offset 5",
            .bytecode = &[_]u8{
                0x60, 0xFF, // PUSH1 0xFF (value)
                0x60, 0x05, // PUSH1 5 (offset)
                0x53, // MSTORE8
                0x00, // STOP
            },
            .expected_stack = &[_]U256{},
            // PUSH1(3) + PUSH1(3) + MSTORE8(3+3) + STOP(0) = 12
            .expected_gas = 12,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "MSIZE: memory size tracking" {
    const test_cases = [_]TestCase{
        .{
            .name = "MSIZE initially zero",
            .bytecode = &[_]u8{
                0x59, // MSIZE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            // MSIZE(2) + STOP(0) = 2
            .expected_gas = 2,
        },
        .{
            .name = "MSIZE after MSTORE",
            .bytecode = &[_]u8{
                0x60, 0x42, // PUSH1 0x42
                0x60, 0x00, // PUSH1 0
                0x52, // MSTORE (expands to 32)
                0x59, // MSIZE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(32)},
            // PUSH1(3) + PUSH1(3) + MSTORE(3+3) + MSIZE(2) + STOP(0) = 14
            .expected_gas = 14,
        },
        .{
            .name = "MSIZE after MSTORE8 at offset 100",
            .bytecode = &[_]u8{
                0x60, 0xFF, // PUSH1 0xFF
                0x60, 0x64, // PUSH1 100 (offset)
                0x53, // MSTORE8 (expands to 128 bytes = 4 words)
                0x59, // MSIZE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(128)},
            // PUSH1(3) + PUSH1(3) + MSTORE8(3 + memoryCost(128)) + MSIZE(2) + STOP(0)
            // memoryCost(128) = (4*3) + (4*4)/512 = 12 + 0 = 12
            // Total: 3 + 3 + 3 + 12 + 2 + 0 = 23
            .expected_gas = 23,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "Memory: complex operations" {
    const test_cases = [_]TestCase{
        .{
            .name = "Multiple MSTORE and MLOAD operations",
            .bytecode = &[_]u8{
                0x60, 0x11, // PUSH1 0x11
                0x60, 0x00, // PUSH1 0
                0x52, // MSTORE at offset 0
                0x60, 0x22, // PUSH1 0x22
                0x60, 0x20, // PUSH1 32
                0x52, // MSTORE at offset 32
                0x60, 0x00, // PUSH1 0
                0x51, // MLOAD offset 0
                0x60, 0x20, // PUSH1 32
                0x51, // MLOAD offset 32
                0x00, // STOP
            },
            .expected_stack = &[_]U256{
                U256.fromU64(0x11),
                U256.fromU64(0x22),
            },
            // PUSH1(3) + PUSH1(3) + MSTORE(3+3) +
            // PUSH1(3) + PUSH1(3) + MSTORE(3+3) +
            // PUSH1(3) + MLOAD(3+0) + PUSH1(3) + MLOAD(3+0) + STOP(0)
            // = 6 + 6 + 6 + 6 + 6 + 6 + 0 = 36
            .expected_gas = 36,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "Memory: gas cost verification" {
    const test_cases = [_]TestCase{
        .{
            .name = "MLOAD with no previous memory access",
            .bytecode = &[_]u8{
                0x60, 0x00, // PUSH1 0
                0x51, // MLOAD (first access, charges expansion)
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            // PUSH1(3) + MLOAD(3 base + 3 expansion) + STOP(0) = 9
            .expected_gas = 9,
        },
        .{
            .name = "Second MLOAD at same offset charges no expansion",
            .bytecode = &[_]u8{
                0x60, 0x00, // PUSH1 0
                0x51, // MLOAD (first access, charges expansion)
                0x60, 0x00, // PUSH1 0
                0x51, // MLOAD (same offset, no expansion)
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO, U256.ZERO},
            // PUSH1(3) + MLOAD(3+3) + PUSH1(3) + MLOAD(3+0) + STOP(0) = 15
            .expected_gas = 15,
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}
