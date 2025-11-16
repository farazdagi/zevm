//! Stack Operations integration tests

const std = @import("std");
const zevm = @import("zevm");
const test_helpers = @import("test_helpers.zig");

const Interpreter = zevm.interpreter.Interpreter;
const ExecutionStatus = zevm.interpreter.ExecutionStatus;
const Spec = zevm.hardfork.Spec;
const U256 = zevm.primitives.U256;
const Address = zevm.primitives.Address;
const Env = zevm.context.Env;
const MockHost = zevm.host.MockHost;
const TestCase = test_helpers.TestCase;
const runOpcodeTests = test_helpers.runOpcodeTests;

// Test helpers
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "PUSH operations" {
    const test_cases = [_]TestCase{
        .{
            .name = "PUSH1 0x42",
            .bytecode = &[_]u8{
                0x60, 0x42, // PUSH1 0x42
                0x00, // STOP
            },
            // Stack: [0x42]
            .expected_stack = &[_]U256{U256.fromU64(0x42)},
            .expected_gas = 3, // PUSH1(3) + STOP(0)
        },
        .{
            .name = "PUSH2 0x1234",
            .bytecode = &[_]u8{
                0x61, 0x12, 0x34, // PUSH2 0x1234
                0x00, // STOP
            },
            // Stack: [0x1234]
            .expected_stack = &[_]U256{U256.fromU64(0x1234)},
            .expected_gas = 3, // PUSH2(3) + STOP(0)
        },
        .{
            .name = "PUSH32 (0x0000...0123)",
            .bytecode = &[_]u8{
                0x7F, // PUSH32
                // 32 bytes: 0x0000...0123
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x01,
                0x23,
                0x00, // STOP
            },
            // Stack: [0x123]
            .expected_stack = &[_]U256{U256.fromU64(0x123)},
            .expected_gas = 3, // PUSH32(3) + STOP(0)
        },
        .{
            .name = "PUSH0 (Shanghai)",
            .bytecode = &[_]u8{
                0x5F, // PUSH0
                0x00, // STOP
            },
            // Stack: [0]
            .expected_stack = &[_]U256{U256.ZERO},
            .expected_gas = 2, // PUSH0(2 - BASE per EIP-3855) + STOP(0)
            .spec = Spec.forFork(.SHANGHAI),
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "PUSH with insufficient bytes" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    // PUSH2 needs 2 bytes but only 1 available
    const bytecode = &[_]u8{ 0x61, 0x42 }; // PUSH2 0x42??
    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.INVALID_PC, result.status);
}

test "PUSH0 not available pre-Shanghai" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN); // PUSH0 not available pre-Shanghai

    const bytecode = &[_]u8{
        0x5F, // PUSH0
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.INVALID_OPCODE, result.status);
}

test "multiple PUSH operations" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x01, // PUSH1 1
        0x60, 0x02, // PUSH1 2
        0x60, 0x03, // PUSH1 3
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(3, interpreter.ctx.stack.len);

    // Stack: [1, 2, 3] (3 on top)
    const top = try interpreter.ctx.stack.peek(0);
    try expectEqual(3, top.toU64().?);
    const second = try interpreter.ctx.stack.peek(1);
    try expectEqual(2, second.toU64().?);
    const third = try interpreter.ctx.stack.peek(2);
    try expectEqual(1, third.toU64().?);
}

test "PC advances correctly with PUSH" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0xFF, // PUSH1 0xFF (PC: 0 -> 2)
        0x61, 0xAA, 0xBB, // PUSH2 0xAABB (PC: 2 -> 5)
        0x00, // STOP (PC: 5)
    };
    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(5, interpreter.pc); // PC at STOP
}

test "POP" {
    const test_cases = [_]TestCase{
        .{
            .name = "POP removes top element",
            .bytecode = &[_]u8{
                0x60, 0x42, // PUSH1 0x42
                0x60, 0x43, // PUSH1 0x43
                0x50, // POP (removes 0x43)
                0x00, // STOP
            },
            // Stack: [0x42] (0x43 was popped)
            .expected_stack = &[_]U256{U256.fromU64(0x42)},
            .expected_gas = 8, // PUSH1(3) + PUSH1(3) + POP(2) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "POP on empty stack" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x50, // POP (empty stack)
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.STACK_UNDERFLOW, result.status);
}

test "DUP operations" {
    const test_cases = [_]TestCase{
        .{
            .name = "DUP1 duplicates top element",
            .bytecode = &[_]u8{
                0x60, 0x42, // PUSH1 0x42
                0x80, // DUP1
                0x00, // STOP
            },
            // Stack: [0x42, 0x42] (bottom to top)
            .expected_stack = &[_]U256{ U256.fromU64(0x42), U256.fromU64(0x42) },
            .expected_gas = 6, // PUSH1(3) + DUP1(3) + STOP(0)
        },
        .{
            .name = "DUP2 duplicates second element",
            .bytecode = &[_]u8{
                0x60, 0x42, // PUSH1 0x42
                0x60, 0x43, // PUSH1 0x43
                0x81, // DUP2 (duplicates 0x42)
                0x00, // STOP
            },
            // Stack: [0x42, 0x43, 0x42] (DUP2 copies second element to top)
            .expected_stack = &[_]U256{
                U256.fromU64(0x42),
                U256.fromU64(0x43),
                U256.fromU64(0x42),
            },
            .expected_gas = 9, // PUSH1(3) + PUSH1(3) + DUP2(3) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "DUP16 duplicates 16th item" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    // Build bytecode with 16 PUSH operations + DUP16 + STOP
    // Each PUSH1 is 2 bytes, plus DUP16 (1 byte) and STOP (1 byte) = 34 bytes
    var bytecode_list = try std.ArrayList(u8).initCapacity(allocator, 34);
    defer bytecode_list.deinit(allocator);

    // Push values 1-16 onto stack
    for (1..17) |i| {
        try bytecode_list.append(allocator, 0x60); // PUSH1
        try bytecode_list.append(allocator, @intCast(i));
    }
    try bytecode_list.append(allocator, 0x8F); // DUP16
    try bytecode_list.append(allocator, 0x00); // STOP

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode_list.items, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(17, interpreter.ctx.stack.len);

    // Top should be 1 (the 16th item from top, which is the first we pushed)
    const top = try interpreter.ctx.stack.peek(0);
    try expectEqual(1, top.toU64().?);
}

test "DUP1 on empty stack fails" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x80, // DUP1 (empty stack)
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.STACK_UNDERFLOW, result.status);
}

test "DUP2 with only one item fails" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x81, // DUP2 (needs 2 items, only has 1)
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.STACK_UNDERFLOW, result.status);
}

test "SWAP operations" {
    const test_cases = [_]TestCase{
        .{
            .name = "SWAP1 swaps top two elements",
            .bytecode = &[_]u8{
                0x60, 0x42, // PUSH1 0x42
                0x60, 0x43, // PUSH1 0x43
                0x90, // SWAP1
                0x00, // STOP
            },
            // Stack: [0x43, 0x42] (swapped from [0x42, 0x43])
            .expected_stack = &[_]U256{ U256.fromU64(0x43), U256.fromU64(0x42) },
            .expected_gas = 9, // PUSH1(3) + PUSH1(3) + SWAP1(3) + STOP(0)
        },
        .{
            .name = "SWAP2 swaps top with third element",
            .bytecode = &[_]u8{
                0x60, 0x41, // PUSH1 0x41
                0x60, 0x42, // PUSH1 0x42
                0x60, 0x43, // PUSH1 0x43
                0x91, // SWAP2
                0x00, // STOP
            },
            // Stack: [0x43, 0x42, 0x41] (top and third swapped)
            .expected_stack = &[_]U256{
                U256.fromU64(0x43),
                U256.fromU64(0x42),
                U256.fromU64(0x41),
            },
            .expected_gas = 12, // PUSH1(3) + PUSH1(3) + PUSH1(3) + SWAP2(3) + STOP(0)
        },
    };
    try runOpcodeTests(std.testing.allocator, &test_cases);
}

test "SWAP16 swaps top with 17th item" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    // Build bytecode with 17 PUSH operations + SWAP16 + STOP
    // Each PUSH1 is 2 bytes, plus SWAP16 (1 byte) and STOP (1 byte) = 36 bytes
    var bytecode_list = try std.ArrayList(u8).initCapacity(allocator, 36);
    defer bytecode_list.deinit(allocator);

    // Push values 1-17 onto stack
    for (1..18) |i| {
        try bytecode_list.append(allocator, 0x60); // PUSH1
        try bytecode_list.append(allocator, @intCast(i));
    }
    try bytecode_list.append(allocator, 0x9F); // SWAP16
    try bytecode_list.append(allocator, 0x00); // STOP

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode_list.items, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(17, interpreter.ctx.stack.len);

    // Top should be 1 (swapped from 17th position)
    const top = try interpreter.ctx.stack.peek(0);
    try expectEqual(1, top.toU64().?);

    // 17th item (index 16) should now be 17
    const seventeenth = try interpreter.ctx.stack.peek(16);
    try expectEqual(17, seventeenth.toU64().?);
}

test "SWAP1 with only one item fails" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x90, // SWAP1 (needs 2 items, only has 1)
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.STACK_UNDERFLOW, result.status);
}

test "SWAP2 with only two items fails" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x11, // PUSH1 0x11
        0x60, 0x22, // PUSH1 0x22
        0x91, // SWAP2 (needs 3 items, only has 2)
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(allocator, bytecode, Address.zero(), spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.STACK_UNDERFLOW, result.status);
}
