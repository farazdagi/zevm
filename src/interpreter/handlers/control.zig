//! Control flow instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Address = @import("../../primitives/address.zig").Address;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Jump to destination (JUMP).
///
/// Stack: [counter, ...] -> [...]
/// Unconditionally jumps to the specified counter if it's a valid JUMPDEST.
///
/// Sets PC directly.
pub fn opJump(interp: *Interpreter) !void {
    const counter_u256 = try interp.ctx.stack.pop();

    // Convert to usize, checking for overflow.
    const counter = counter_u256.toUsize() orelse return error.InvalidJump;

    // Validate destination.
    if (!interp.ctx.contract.bytecode.isValidJump(counter)) {
        return error.InvalidJump;
    }

    interp.pc = counter;
}

/// Conditional jump (JUMPI).
///
/// Stack: [counter, b, ...] -> [...]
/// Jumps to counter if b != 0, otherwise continues to next instruction.
/// Sets interp.pc if jumping; leaves it unchanged if not (step() will auto-increment).
pub fn opJumpi(interp: *Interpreter) !void {
    const counter_u256 = try interp.ctx.stack.pop();
    const b = try interp.ctx.stack.pop();

    // If condition is zero, don't jump (PC will auto-increment).
    if (b.isZero()) {
        return;
    }

    // Convert to usize, checking for overflow.
    const counter = counter_u256.toUsize() orelse return error.InvalidJump;

    // Validate destination
    if (!interp.ctx.contract.bytecode.isValidJump(counter)) {
        return error.InvalidJump;
    }

    interp.pc = counter;
}

/// Get program counter (PC).
///
/// Stack: [...] -> [..., pc]
/// Returns the current value of the program counter (the position of this PC instruction).
pub fn opPc(interp: *Interpreter) !void {
    try interp.ctx.stack.push(U256.fromU64(@intCast(interp.pc)));
}

/// Get remaining gas (GAS).
///
/// Stack: [...] -> [..., gas]
/// Returns the amount of available gas after this instruction.
/// The gas value pushed is AFTER charging the base cost of the GAS opcode itself.
pub fn opGas(interp: *Interpreter) !void {
    const remaining = interp.gas.remaining();
    try interp.ctx.stack.push(U256.fromU64(remaining));
}

/// Halt execution and return data (RETURN).
///
/// Stack: [offset, size, ...] -> []
/// Halts execution and returns data from memory.
/// Sets interp.return_data and interp.is_halted.
/// Gas is charged by the interpreter before calling this handler.
pub fn opReturn(interp: *Interpreter) !void {
    const offset_u256 = try interp.ctx.stack.pop();
    const size_u256 = try interp.ctx.stack.pop();

    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const size = size_u256.toUsize() orelse return error.InvalidOffset;

    // Handle empty return data case
    if (size == 0) {
        interp.return_data = &[_]u8{};
        interp.is_halted = true;
        return;
    }

    // Expand memory if needed
    try interp.ctx.memory.ensureCapacity(offset, size);

    // Get output data from memory
    const output = try interp.ctx.memory.getSlice(offset, size);

    // Allocate owned copy
    const owned_output = try interp.allocator.dupe(u8, output);
    interp.return_data = owned_output;
    interp.is_halted = true;
}

/// Halt execution and revert state changes (REVERT).
///
/// Stack: [offset, size, ...] -> []
/// Halts execution, reverts state, and returns error data from memory.
/// Sets interp.return_data and returns error.Revert.
/// Available from Byzantium (EIP-140) onwards.
/// Gas is charged by the interpreter before calling this handler.
pub fn opRevert(interp: *Interpreter) !void {
    const offset_u256 = try interp.ctx.stack.pop();
    const size_u256 = try interp.ctx.stack.pop();

    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const size = size_u256.toUsize() orelse return error.InvalidOffset;

    // Handle empty revert data case
    if (size == 0) {
        interp.return_data = &[_]u8{};
        return error.Revert;
    }

    // Expand memory if needed
    try interp.ctx.memory.ensureCapacity(offset, size);

    // Get output data from memory
    const output = try interp.ctx.memory.getSlice(offset, size);

    // Allocate owned copy
    const owned_output = try interp.allocator.dupe(u8, output);
    interp.return_data = owned_output;
    return error.Revert;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const test_helpers = @import("test_helpers.zig");

test "PC returns current program counter" {
    const bytecode = [_]u8{0x00}; // STOP
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    // Set PC to 10
    ctx.interp.pc = 10;
    try opPc(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(10, result.toU64().?);
}

test "GAS returns remaining gas" {
    const bytecode = [_]u8{0x00}; // STOP
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    // Consume some gas
    try ctx.interp.gas.consume(30);

    // GAS opcode should return remaining gas
    try opGas(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    const expected = 1000000 - 30;
    try expectEqual(expected, result.toU64().?);
}

test "JUMP to valid JUMPDEST" {
    const bytecode = [_]u8{ 0x5B, 0x00 }; // JUMPDEST at 0, STOP
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // Jump to position 0
    try opJump(&ctx.interp);

    // PC should be set to 0
    try expectEqual(0, ctx.interp.pc);
}

test "JUMP to invalid destination fails" {
    const bytecode = [_]u8{ 0x00, 0x5B }; // STOP, JUMPDEST
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // Try to jump to STOP (invalid)
    try expectError(error.InvalidJump, opJump(&ctx.interp));
}

test "JUMP out of bounds fails" {
    const bytecode = [_]u8{0x5B}; // JUMPDEST
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    try ctx.interp.ctx.stack.push(U256.fromU64(100)); // Out of bounds
    try expectError(error.InvalidJump, opJump(&ctx.interp));
}

test "JUMPI with true condition jumps" {
    const bytecode = [_]u8{0x5B}; // JUMPDEST at 0
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    try ctx.interp.ctx.stack.push(U256.fromU64(1)); // condition = true
    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // destination = 0

    ctx.interp.pc = 5; // Set PC to non-zero
    try opJumpi(&ctx.interp);

    // PC should be set to 0 (jumped)
    try expectEqual(0, ctx.interp.pc);
}

test "JUMPI with false condition doesn't jump" {
    const bytecode = [_]u8{0x5B}; // JUMPDEST at 0
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // condition = false
    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // destination = 0

    ctx.interp.pc = 5; // Set PC to non-zero
    try opJumpi(&ctx.interp);

    // PC should remain 5 (didn't jump)
    try expectEqual(5, ctx.interp.pc);
}

test "JUMPI with true condition to invalid destination fails" {
    const bytecode = [_]u8{ 0x00, 0x5B }; // STOP, JUMPDEST
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    try ctx.interp.ctx.stack.push(U256.fromU64(1)); // condition = true
    try ctx.interp.ctx.stack.push(U256.fromU64(0)); // destination = 0 (invalid)

    try expectError(error.InvalidJump, opJumpi(&ctx.interp));
}

test "RETURN with zero size" {
    const bytecode = [_]u8{0x00}; // STOP
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    try ctx.interp.ctx.stack.push(U256.ZERO); // size = 0
    try ctx.interp.ctx.stack.push(U256.ZERO); // offset = 0

    try opReturn(&ctx.interp);

    try expect(ctx.interp.is_halted);
    try expectEqual(0, ctx.interp.return_data.?.len);
}

test "RETURN with data" {
    const bytecode = [_]u8{0x00}; // STOP
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();
    defer if (ctx.interp.return_data) |data| ctx.interp.allocator.free(data);

    // Store some data in memory
    try ctx.interp.ctx.memory.mstore(0, U256.fromU64(0x42));

    try ctx.interp.ctx.stack.push(U256.fromU64(32)); // size = 32 bytes
    try ctx.interp.ctx.stack.push(U256.ZERO); // offset = 0

    try opReturn(&ctx.interp);

    try expect(ctx.interp.is_halted);
    try expectEqual(32, ctx.interp.return_data.?.len);
}

test "REVERT with zero size" {
    const bytecode = [_]u8{0x00}; // STOP
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();

    try ctx.interp.ctx.stack.push(U256.ZERO); // size = 0
    try ctx.interp.ctx.stack.push(U256.ZERO); // offset = 0

    try expectError(error.Revert, opRevert(&ctx.interp));
    try expectEqual(0, ctx.interp.return_data.?.len);
}

test "REVERT with data" {
    const bytecode = [_]u8{0x00}; // STOP
    var ctx = try test_helpers.TestContext.createWithBytecode(std.testing.allocator, &bytecode, Address.zero());
    defer ctx.destroy();
    defer if (ctx.interp.return_data) |data| ctx.interp.allocator.free(data);

    // Store some data in memory
    try ctx.interp.ctx.memory.mstore(0, U256.fromU64(0x99));

    try ctx.interp.ctx.stack.push(U256.fromU64(32)); // size = 32 bytes
    try ctx.interp.ctx.stack.push(U256.ZERO); // offset = 0

    try expectError(error.Revert, opRevert(&ctx.interp));
    try expectEqual(32, ctx.interp.return_data.?.len);
}
