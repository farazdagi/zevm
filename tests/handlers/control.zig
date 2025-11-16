//! Integration tests for control flow operations.

const std = @import("std");
const zevm = @import("zevm");

const Interpreter = zevm.interpreter.Interpreter;
const ExecutionStatus = zevm.interpreter.ExecutionStatus;
const Spec = zevm.hardfork.Spec;
const Hardfork = zevm.hardfork.Hardfork;
const U256 = zevm.primitives.U256;
const Address = zevm.primitives.Address;
const Env = zevm.context.Env;
const MockHost = zevm.host.MockHost;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "JUMP: simple forward jump" {
    // PUSH1 0x05, JUMP, INVALID, INVALID, JUMPDEST, PUSH1 0x42, STOP
    const bytecode = [_]u8{
        0x60, 0x05, // PUSH1 5
        0x56, // JUMP
        0xFE, // INVALID (skipped)
        0xFE, // INVALID (skipped)
        0x5B, // JUMPDEST (position 5)
        0x60, 0x42, // PUSH1 0x42
        0x00, // STOP
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.CANCUN),
        100000,
        &env,
        mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();

    // Should have executed the jump and pushed 0x42
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(1, interpreter.ctx.stack.len);
    const value = try interpreter.ctx.stack.pop();
    try expectEqual(0x42, value.toU64().?);
}

test "JUMPI: conditional jump taken" {
    // Stack for JUMPI needs [counter, condition] with counter on top
    // So push condition first, then counter
    const bytecode = [_]u8{
        0x60, 0x01, // PUSH1 1 (condition true) - pos 0-1
        0x60, 0x07, // PUSH1 7 (counter/destination) - pos 2-3
        0x57, // JUMPI - pos 4
        0xFE, // INVALID (skipped) - pos 5
        0xFE, // INVALID (skipped) - pos 6
        0x5B, // JUMPDEST - pos 7
        0x60, 0x99, // PUSH1 0x99 - pos 8-9
        0x00, // STOP - pos 10
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();
    
    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.CANCUN),
        100000,
            &env,
            mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();

    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.ctx.stack.pop();
    try expectEqual(0x99, value.toU64().?);
}

test "JUMPI: conditional jump not taken" {
    // Stack for JUMPI needs [counter, condition] with counter on top
    // So push condition first, then counter
    const bytecode = [_]u8{
        0x60, 0x00, // PUSH1 0 (condition false) - pos 0-1
        0x60, 0x08, // PUSH1 8 (destination) - pos 2-3
        0x57, // JUMPI - pos 4
        0x60, 0x77, // PUSH1 0x77 (executed) - pos 5-6
        0x00, // STOP - pos 7
        0x5B, // JUMPDEST (not reached) - pos 8
        0x60, 0x99, // PUSH1 0x99 - pos 9-10
        0x00, // STOP - pos 11
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();
    
    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.CANCUN),
        100000,
            &env,
            mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();

    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.ctx.stack.pop();
    try expectEqual(0x77, value.toU64().?); // Not 0x99
}

test "loop: simple counter loop" {
    // Initialize counter to 3, decrement until 0
    // Per EVM semantics: PUSH1 a; PUSH1 b; SUB computes b-a (first_pop - second_pop)
    // To compute counter-1: DUP counter, PUSH1 1, SWAP1, SUB
    const bytecode = [_]u8{
        0x60, 0x03, // PUSH1 3 (initial counter) - pos 0-1
        0x5B, // JUMPDEST - pos 2
        0x80, // DUP1 (duplicate counter) - pos 3
        0x60, 0x01, // PUSH1 1 - pos 4-5
        0x90, // SWAP1 (now stack is [counter, 1] with counter on top) - pos 6
        0x03, // SUB (counter - 1) - pos 7
        0x80, // DUP1 (duplicate result for condition check) - pos 8
        0x60, 0x02, // PUSH1 2 (jump destination) - pos 9-10
        0x57, // JUMPI (jump if counter != 0) - pos 11
        0x00, // STOP - pos 12
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();
    
    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.CANCUN),
        100000,
            &env,
            mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();

    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    // Final counter value should be 0
    const value = try interpreter.ctx.stack.pop();
    try expectEqual(0, value.toU64().?);
}

test "RETURN: empty return data" {
    // PUSH1 0x00, PUSH1 0x00, RETURN
    const bytecode = [_]u8{
        0x60, 0x00, // PUSH1 0 (size)
        0x60, 0x00, // PUSH1 0 (offset)
        0xF3, // RETURN
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();
    
    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.CANCUN),
        100000,
            &env,
            mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();

    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expect(result.return_data != null);
    try expectEqual(0, result.return_data.?.len);
}

test "RETURN: with data in memory" {
    // Store 0x1234 at memory offset 0, return 32 bytes
    // PUSH2 0x1234, PUSH1 0x00, MSTORE, PUSH1 0x20, PUSH1 0x00, RETURN
    const bytecode = [_]u8{
        0x61, 0x12, 0x34, // PUSH2 0x1234
        0x60, 0x00, // PUSH1 0 (offset)
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32 (size)
        0x60, 0x00, // PUSH1 0 (offset)
        0xF3, // RETURN
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();
    
    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.CANCUN),
        100000,
            &env,
            mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();
    defer if (result.return_data) |data| std.testing.allocator.free(data);

    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expect(result.return_data != null);
    try expectEqual(32, result.return_data.?.len);

    // Verify the data (0x1234 stored at offset 0, right-aligned in 32 bytes)
    // Last 2 bytes should be 0x12, 0x34
    const data = result.return_data.?;
    try expectEqual(0x12, data[30]);
    try expectEqual(0x34, data[31]);
}

test "REVERT: with error message" {
    // Store error data, then revert
    // PUSH1 0xFF, PUSH1 0x00, MSTORE8, PUSH1 0x01, PUSH1 0x00, REVERT
    const bytecode = [_]u8{
        0x60, 0xFF, // PUSH1 0xFF
        0x60, 0x00, // PUSH1 0 (offset)
        0x53, // MSTORE8
        0x60, 0x01, // PUSH1 1 (size)
        0x60, 0x00, // PUSH1 0 (offset)
        0xFD, // REVERT
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();
    
    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.BYZANTIUM), // REVERT added in Byzantium
        100000,
            &env,
            mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();
    defer if (result.return_data) |data| std.testing.allocator.free(data);

    try expectEqual(ExecutionStatus.REVERT, result.status);
    try expect(result.return_data != null);
    try expectEqual(1, result.return_data.?.len);
    try expectEqual(0xFF, result.return_data.?[0]);
}

test "PC and GAS opcodes" {
    // PC, PUSH1 0x00, EQ, GAS, STOP
    const bytecode = [_]u8{
        0x58, // PC (should push 0)
        0x60, 0x00, // PUSH1 0
        0x14, // EQ (check PC == 0)
        0x5A, // GAS
        0x00, // STOP
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();
    
    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.CANCUN),
        100000,
            &env,
            mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();

    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    // Stack should have: [gas_remaining, 1 (PC==0)]
    try expectEqual(2, interpreter.ctx.stack.len);

    // Gas costs: PC(2) + PUSH1(3) + EQ(3) + GAS(2) + STOP(0) = 10 gas total
    const gas_val = try interpreter.ctx.stack.pop();
    try expectEqual(99990, gas_val.toU64().?); // 100000 - 10

    const eq_result = try interpreter.ctx.stack.pop();
    try expectEqual(1, eq_result.toU64().?); // PC was 0

    // Verify total gas consumed
    try expectEqual(10, result.gas_used);
}

test "INVALID: consumes all gas" {
    // PUSH1 0x42, INVALID, PUSH1 0x99
    const bytecode = [_]u8{
        0x60, 0x42, // PUSH1 0x42
        0xFE, // INVALID
        0x60, 0x99, // PUSH1 0x99 (never executed)
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();
    
    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.CANCUN),
        100000,
            &env,
            mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();

    try expectEqual(ExecutionStatus.INVALID_OPCODE, result.status);
    // Should have consumed all gas
    try expectEqual(100000, result.gas_used);
    // Stack should only have the first PUSH (0x42), not the second
    try expectEqual(1, interpreter.ctx.stack.len);
}

test "JUMP: invalid destination error" {
    // PUSH1 0x00, JUMP (try to jump to PUSH, not JUMPDEST)
    const bytecode = [_]u8{
        0x60, 0x00, // PUSH1 0 (invalid destination)
        0x56, // JUMP
    };

    const env = Env.default();
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();
    
    var interpreter = try Interpreter.init(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
        Spec.forFork(.CANCUN),
        100000,
            &env,
            mock.host(),
    );
    defer interpreter.deinit();

    const result = try interpreter.run();

    try expectEqual(ExecutionStatus.INVALID_JUMP, result.status);
}
