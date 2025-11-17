//! Basic Interpreter integration tests

const std = @import("std");
const zevm = @import("zevm");

const Interpreter = zevm.interpreter.Interpreter;
const CallContext = zevm.interpreter.CallContext;
const ExecutionStatus = zevm.interpreter.ExecutionStatus;
const Spec = zevm.hardfork.Spec;
const U256 = zevm.primitives.U256;
const Address = zevm.primitives.Address;
const Env = zevm.context.Env;
const MockHost = zevm.host.MockHost;
const Evm = zevm.Evm;

// Test helpers
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "init and deinit" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{0x00}; // STOP
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 1000, &env, mock.host());
    defer interpreter.deinit();

    try expectEqual(0, interpreter.pc);
    try expect(!interpreter.is_halted);
    try expectEqual(1000, interpreter.gas.limit);
    try expectEqual(0, interpreter.gas.used);
}

test "empty bytecode" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode: []const u8 = &[_]u8{};
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 1000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.INVALID_PC, result.status);
}

test "STOP halts execution" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{0x00}; // STOP
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 1000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(0, result.gas_used); // STOP costs 0 gas
    try expect(interpreter.is_halted);
}

test "multiple STOP opcodes (only first executed)" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{ 0x00, 0x00, 0x00 }; // STOP STOP STOP
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 1000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    try expectEqual(0, interpreter.pc); // PC stays at 0 (STOP is control flow)
    try expectEqual(0, result.gas_used);
}

test "invalid opcode" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{0x0C}; // Invalid opcode (gap in spec)
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 1000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.INVALID_OPCODE, result.status);
}

test "unimplemented opcode" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{0x54}; // SLOAD (not yet implemented)
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 1000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.INVALID_OPCODE, result.status);
}

test "out of gas" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    // PUSH1 costs 3 gas, but we only have 2
    const bytecode = &[_]u8{ 0x60, 0x01 }; // PUSH1 1
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 2, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.OUT_OF_GAS, result.status);
}

test "Stack overflow - 1025 PUSH operations" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    // Build bytecode with 1025 PUSH1 operations (stack limit is 1024)
    // Each PUSH1 is 2 bytes (opcode + value), plus 1 STOP = 2051 bytes
    const bytecode = try allocator.alloc(u8, 1025 * 2 + 1);
    defer allocator.free(bytecode);

    var idx: usize = 0;
    for (0..1025) |_| {
        bytecode[idx] = 0x60; // PUSH1
        bytecode[idx + 1] = 0x01; // value
        idx += 2;
    }
    bytecode[idx] = 0x00; // STOP

    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 1000000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.STACK_OVERFLOW, result.status);
}

test "Stack underflow - ADD with only one item" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    const bytecode = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x01, // ADD (needs 2 items, only has 1)
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.STACK_UNDERFLOW, result.status);
}

test "Complex calculation - Fibonacci-like" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    // Calculate: a=1, b=2, c=a+b, result=c*2
    // Expected: (1+2)*2 = 6
    const bytecode = &[_]u8{
        0x60, 0x01, // PUSH1 1    -> [1]
        0x60, 0x02, // PUSH1 2    -> [1, 2]
        0x60, 0x01, // PUSH1 1    -> [1, 2, 1]  (for DUP later, but we inline)
        0x60, 0x02, // PUSH1 2    -> [1, 2, 1, 2]
        0x01, // ADD        -> [1, 2, 3]
        0x60, 0x02, // PUSH1 2    -> [1, 2, 3, 2]
        0x02, // MUL        -> [1, 2, 6]
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const top = try interpreter.ctx.stack.peek(0);
    try expectEqual(6, top.toU64().?);
}

test "Chained operations with mixed ops" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.BERLIN);

    // (10 / 2) + (3 * 4) = 5 + 12 = 17
    const bytecode = &[_]u8{
        0x60, 0x02, // PUSH1 2 (second operand, pushed first)
        0x60, 0x0A, // PUSH1 10 (first operand, on top)
        0x04, // DIV -> computes 10 / 2 = 5
        0x60, 0x03, // PUSH1 3
        0x60, 0x04, // PUSH1 4
        0x02, // MUL -> computes 3 * 4 = 12 (MUL is commutative)
        0x01, // ADD -> computes 5 + 12 = 17 (ADD is commutative)
        0x00, // STOP
    };
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero());
    var interpreter = Interpreter.init(allocator, ctx, spec, 10000, &env, mock.host());
    defer interpreter.deinit();

    const result = try interpreter.run(&evm);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);
    const value = try interpreter.ctx.stack.peek(0);
    try expectEqual(17, value.toU64().?);
}
