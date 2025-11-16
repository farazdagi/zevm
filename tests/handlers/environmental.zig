//! Integration tests for environmental handler opcodes.

const std = @import("std");
const zevm = @import("zevm");
const U256 = zevm.primitives.U256;
const Address = zevm.primitives.Address;

const test_helpers = @import("test_helpers.zig");
const TestCase = test_helpers.TestCase;
const runOpcodeTests = test_helpers.runOpcodeTests;

const expectEqual = std.testing.expectEqual;

test "Environmental context" {
    const test_cases = [_]TestCase{
        // ADDRESS returns contract address (Address.zero() in test env)
        .{
            .name = "ADDRESS",
            .bytecode = &[_]u8{
                0x30, // ADDRESS
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 2, // ADDRESS(2) + STOP(0)
        },
        // ORIGIN returns transaction origin (Address.zero() in test env)
        .{
            .name = "ORIGIN",
            .bytecode = &[_]u8{
                0x32, // ORIGIN
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 2, // ORIGIN(2) + STOP(0)
        },
        // CALLER returns transaction caller (Address.zero() in test env)
        .{
            .name = "CALLER",
            .bytecode = &[_]u8{
                0x33, // CALLER
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 2, // CALLER(2) + STOP(0)
        },
        // CALLVALUE returns transaction value (0 in test env)
        .{
            .name = "CALLVALUE",
            .bytecode = &[_]u8{
                0x34, // CALLVALUE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 2, // CALLVALUE(2) + STOP(0)
        },
        // CALLDATASIZE returns calldata length (empty in test env)
        .{
            .name = "CALLDATASIZE",
            .bytecode = &[_]u8{
                0x36, // CALLDATASIZE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 2, // CALLDATASIZE(2) + STOP(0)
        },
        // CODESIZE returns bytecode length (2 bytes: CODESIZE + STOP)
        .{
            .name = "CODESIZE",
            .bytecode = &[_]u8{
                0x38, // CODESIZE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(2)},
            .expected_gas = 2, // CODESIZE(2) + STOP(0)
        },
        // COINBASE returns block coinbase (Address.zero() in test env)
        .{
            .name = "COINBASE",
            .bytecode = &[_]u8{
                0x41, // COINBASE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 2, // COINBASE(2) + STOP(0)
        },
        // TIMESTAMP returns block timestamp (0 in test env)
        .{
            .name = "TIMESTAMP",
            .bytecode = &[_]u8{
                0x42, // TIMESTAMP
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 2, // TIMESTAMP(2) + STOP(0)
        },
        // NUMBER returns block number (1 in test env from BlockEnv.default())
        .{
            .name = "NUMBER",
            .bytecode = &[_]u8{
                0x43, // NUMBER
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(1)},
            .expected_gas = 2, // NUMBER(2) + STOP(0)
        },
        // GASLIMIT returns block gas limit (30_000_000 in test env)
        .{
            .name = "GASLIMIT",
            .bytecode = &[_]u8{
                0x45, // GASLIMIT
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(30_000_000)},
            .expected_gas = 2, // GASLIMIT(2) + STOP(0)
        },
        // CHAINID returns chain ID (1 = mainnet in test env)
        .{
            .name = "CHAINID",
            .bytecode = &[_]u8{
                0x46, // CHAINID
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(1)},
            .expected_gas = 2, // CHAINID(2) + STOP(0)
        },
        // GASPRICE returns gas price (1 in test env)
        .{
            .name = "GASPRICE",
            .bytecode = &[_]u8{
                0x3A, // GASPRICE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.fromU64(1)},
            .expected_gas = 2, // GASPRICE(2) + STOP(0)
        },
        // BASEFEE returns base fee per gas (0 in test env)
        .{
            .name = "BASEFEE",
            .bytecode = &[_]u8{
                0x48, // BASEFEE
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 2, // BASEFEE(2) + STOP(0)
        },
        // CODECOPY copies bytecode to memory
        .{
            .name = "CODECOPY",
            .bytecode = &[_]u8{
                0x60, 0x04, // PUSH1 4  (length - copy 4 bytes)
                0x60, 0x00, // PUSH1 0  (code offset)
                0x60, 0x00, // PUSH1 0  (memory dest offset)
                0x39, // CODECOPY
                0x00, // STOP
            },
            .expected_stack = &[_]U256{}, // Stack is empty after CODECOPY
            .expected_gas = 18, // PUSH1(3) + PUSH1(3) + PUSH1(3) + CODECOPY(3 + 3*1 + 3 for memory) + STOP(0)
        },
        // CODECOPY with zero length
        .{
            .name = "CODECOPY zero length",
            .bytecode = &[_]u8{
                0x60, 0x00, // PUSH1 0  (length)
                0x60, 0x00, // PUSH1 0  (code offset)
                0x60, 0x00, // PUSH1 0  (memory dest offset)
                0x39, // CODECOPY
                0x00, // STOP
            },
            .expected_stack = &[_]U256{},
            .expected_gas = 12, // PUSH1(3) * 3 + CODECOPY(3) + STOP(0)
        },
        // CALLDATACOPY with zero length is no-op
        .{
            .name = "CALLDATACOPY zero length",
            .bytecode = &[_]u8{
                0x60, 0x00, // PUSH1 0  (length)
                0x60, 0x00, // PUSH1 0  (calldata offset)
                0x60, 0x00, // PUSH1 0  (memory dest)
                0x37, // CALLDATACOPY
                0x00, // STOP
            },
            .expected_stack = &[_]U256{},
            .expected_gas = 12, // PUSH1(3) * 3 + CALLDATACOPY(3) + STOP(0)
        },
    };

    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "CALLDATALOAD edge cases" {
    const test_cases = [_]TestCase{
        // CALLDATALOAD from offset 0 with empty calldata returns zeros
        .{
            .name = "CALLDATALOAD empty calldata",
            .bytecode = &[_]u8{
                0x60, 0x00, // PUSH1 0  (offset)
                0x35, // CALLDATALOAD
                0x00, // STOP
            },
            .expected_stack = &[_]U256{U256.ZERO}, // All zeros since calldata is empty
            .expected_gas = 6, // PUSH1(3) + CALLDATALOAD(3) + STOP(0)
        },
    };

    try runOpcodeTests(std.testing.allocator, &test_cases);
}
