//! Stack Operations integration tests

const std = @import("std");
const zevm = @import("zevm");

const Interpreter = zevm.interpreter.Interpreter;
const ExecutionStatus = zevm.interpreter.ExecutionStatus;
const Spec = zevm.hardfork.Spec;
const U256 = zevm.primitives.U256;

// Test helpers
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "PUSH1 pushes 1 byte" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(1, interpreter.stack.len);
    const value = try interpreter.stack.peek(0);
    try expectEqual(0x42, value.toU64().?);
}

test "PUSH2 pushes 2 bytes" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x61, 0x12, 0x34, // PUSH2 0x1234
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(0x1234, value.toU64().?);
}

test "PUSH32 pushes 32 bytes" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
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
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expectEqual(0x123, value.toU64().?);
}

test "PUSH with insufficient bytes" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    // PUSH2 needs 2 bytes but only 1 available
    const bytecode = &[_]u8{ 0x61, 0x42 }; // PUSH2 0x42??
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.INVALID_OPCODE, result.status);
}

test "PUSH0 (Shanghai+)" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.SHANGHAI); // PUSH0 available in Shanghai+

    const bytecode = &[_]u8{
        0x5F, // PUSH0
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.stack.peek(0);
    try expect(value.isZero());
}

test "PUSH0 not available pre-Shanghai" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN); // PUSH0 not available pre-Shanghai

    const bytecode = &[_]u8{
        0x5F, // PUSH0
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
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
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(3, interpreter.stack.len);

    // Stack: [1, 2, 3] (3 on top)
    const top = try interpreter.stack.peek(0);
    try expectEqual(3, top.toU64().?);
    const second = try interpreter.stack.peek(1);
    try expectEqual(2, second.toU64().?);
    const third = try interpreter.stack.peek(2);
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
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(5, interpreter.pc); // PC at STOP
}

test "POP removes item from stack" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x60, 0x43, // PUSH1 0x43
        0x50, // POP (removes 0x43)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(1, interpreter.stack.len);
    const value = try interpreter.stack.peek(0);
    try expectEqual(0x42, value.toU64().?);
}

test "POP on empty stack" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x50, // POP (empty stack)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.STACK_UNDERFLOW, result.status);
}

test "DUP1 duplicates top of stack" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x80, // DUP1
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(2, interpreter.stack.len);

    const top = try interpreter.stack.peek(0);
    const second = try interpreter.stack.peek(1);
    try expectEqual(0x42, top.toU64().?);
    try expectEqual(0x42, second.toU64().?);
}

test "DUP2 duplicates second item" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x11, // PUSH1 0x11
        0x60, 0x22, // PUSH1 0x22
        0x81, // DUP2 (duplicates 0x11)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(3, interpreter.stack.len);

    // Stack should be [0x11, 0x22, 0x11] (top to bottom)
    const top = try interpreter.stack.peek(0);
    const second = try interpreter.stack.peek(1);
    const third = try interpreter.stack.peek(2);
    try expectEqual(0x11, top.toU64().?);
    try expectEqual(0x22, second.toU64().?);
    try expectEqual(0x11, third.toU64().?);
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

    var interpreter = try Interpreter.init(allocator, bytecode_list.items, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(17, interpreter.stack.len);

    // Top should be 1 (the 16th item from top, which is the first we pushed)
    const top = try interpreter.stack.peek(0);
    try expectEqual(1, top.toU64().?);
}

test "DUP1 on empty stack fails" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x80, // DUP1 (empty stack)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
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
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.STACK_UNDERFLOW, result.status);
}

test "DUP gas consumption" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x42, // PUSH1 0x42  (3 gas)
        0x80, // DUP1        (3 gas)
        0x00, // STOP        (0 gas)
    };
    // Total: 6 gas

    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(6, result.gas_used);
}

test "SWAP1 swaps top two items" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x11, // PUSH1 0x11
        0x60, 0x22, // PUSH1 0x22
        0x90, // SWAP1
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(2, interpreter.stack.len);

    // Stack should be [0x22, 0x11] swapped to [0x11, 0x22]
    const top = try interpreter.stack.peek(0);
    const second = try interpreter.stack.peek(1);
    try expectEqual(0x11, top.toU64().?);
    try expectEqual(0x22, second.toU64().?);
}

test "SWAP2 swaps top with third item" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x11, // PUSH1 0x11
        0x60, 0x22, // PUSH1 0x22
        0x60, 0x33, // PUSH1 0x33
        0x91, // SWAP2 (swaps 0x33 with 0x11)
        0x00, // STOP
    };
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(3, interpreter.stack.len);

    // Stack was [0x11, 0x22, 0x33], after SWAP2: [0x33, 0x22, 0x11]
    const top = try interpreter.stack.peek(0);
    const second = try interpreter.stack.peek(1);
    const third = try interpreter.stack.peek(2);
    try expectEqual(0x11, top.toU64().?);
    try expectEqual(0x22, second.toU64().?);
    try expectEqual(0x33, third.toU64().?);
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

    var interpreter = try Interpreter.init(allocator, bytecode_list.items, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(17, interpreter.stack.len);

    // Top should be 1 (swapped from 17th position)
    const top = try interpreter.stack.peek(0);
    try expectEqual(1, top.toU64().?);

    // 17th item (index 16) should now be 17
    const seventeenth = try interpreter.stack.peek(16);
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
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
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
    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.STACK_UNDERFLOW, result.status);
}

test "SWAP gas consumption" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x11, // PUSH1 0x11  (3 gas)
        0x60, 0x22, // PUSH1 0x22  (3 gas)
        0x90, // SWAP1       (3 gas)
        0x00, // STOP        (0 gas)
    };
    // Total: 9 gas

    var interpreter = try Interpreter.init(allocator, bytecode, spec, 10000);
    defer interpreter.deinit();

    const result = try interpreter.run();
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(9, result.gas_used);
}
