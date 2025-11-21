//! Storage operation instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Interpreter = @import("../interpreter.zig").Interpreter;
const sstore = @import("../../gas/sstore.zig");

/// Load word from storage (SLOAD).
///
/// Stack: [key, ...] -> [value, ...]
///
/// Gas: Base cost from hardfork table + dynamic cold/warm cost from DynamicGasCosts.opSload.
pub fn opSload(interp: *Interpreter) !void {
    // Get mutable pointer to key (will be replaced with value).
    const key_ptr = try interp.ctx.stack.peekMut(0);

    // Load value from storage and replace value on stack.
    key_ptr.* = interp.host.sload(interp.ctx.contract.address, key_ptr.*);
}

/// Store word to storage (SSTORE).
///
/// Stack: [key, value, ...] -> [...]
///
/// NOTE: This handler calculates gas internally rather than using dynamicGasCost.
/// This is because SSTORE gas depends on the result of the storage write (original/current values).
/// The write happens first, then gas is charged. If OutOfGas occurs, the entire call frame
/// reverts via snapshot/revert, undoing the write.
///
/// IMPORTANT: hardfork.zig must set dynamicGasCost = null for SSTORE.
pub fn opSstore(interp: *Interpreter) !void {
    // SSTORE forbidden in static context.
    if (interp.is_static) {
        return error.StateWriteInStaticCall;
    }

    // EIP-2200: Require gas > CALL_STIPEND (2300).
    // This prevents reentrancy attacks via the gas stipend given to callees.
    if (interp.gas.remaining() <= interp.spec.call_stipend) {
        return error.OutOfGas;
    }

    // Obtain key and value from stack.
    const key = try interp.ctx.stack.pop();
    const new_value = try interp.ctx.stack.pop();

    // Touch the slot (warms it) and obtain its previous state.
    const is_cold = interp.access_list.warmSlot(interp.ctx.contract.address, key);

    // Execute write AND get original/current values (for gas metering).
    const result = interp.host.sstore(interp.ctx.contract.address, key, new_value);

    // Calculate and charge gas (OutOfGas here causes frame revert, undoing write).
    const gas_cost = sstore.sstoreCost(interp.spec, result, new_value, is_cold);
    try interp.gas.consume(gas_cost);

    // Record refund (can be positive or negative).
    const refund = sstore.sstoreRefund(interp.spec, result, new_value);
    interp.gas.adjustRefund(refund);
}

/// Load word from transient storage (TLOAD) - EIP-1153.
///
/// Stack: [key, ...] -> [value, ...]
///
/// Gas: Fixed 100 (warm storage read cost). Available Cancun+.
pub fn opTload(interp: *Interpreter) !void {
    // Get mutable pointer to key (will be replaced with value).
    const key_ptr = try interp.ctx.stack.peekMut(0);

    // Load value from transient storage and push it on stack.
    key_ptr.* = interp.host.tload(interp.ctx.contract.address, key_ptr.*);
}

/// Store word to transient storage (TSTORE) - EIP-1153.
///
/// Stack: [key, value, ...] -> [...]
///
/// Gas: Fixed 100 (warm storage read cost). Available Cancun+.
/// Transient storage is cleared at end of transaction.
pub fn opTstore(interp: *Interpreter) !void {
    // TSTORE is not allowed in static call context (STATICCALL).
    if (interp.is_static) {
        return error.StateWriteInStaticCall;
    }

    // Obtain key and value from stack.
    const key = try interp.ctx.stack.pop();
    const value = try interp.ctx.stack.pop();

    // Write to transient storage via host.
    interp.host.tstore(interp.ctx.contract.address, key, value);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
const TestContext = @import("test_helpers.zig").TestContext;

test "SLOAD operations" {
    const test_cases = [_]struct {
        initial_value: ?U256,
        expected_result: U256,
    }{
        // Reads value from storage.
        .{
            .initial_value = U256.fromU64(100),
            .expected_result = U256.fromU64(100),
        },
        // Uninitialized slot returns zero.
        .{
            .initial_value = null,
            .expected_result = U256.ZERO,
        },
    };

    for (test_cases) |tc| {
        const ctx = try TestContext.create(testing.allocator);
        defer ctx.destroy();

        const key = U256.fromU64(42);

        // Set up storage if initial value specified.
        if (tc.initial_value) |value| {
            try ctx.mock.setStorage(ctx.interp.ctx.contract.address, key, value);
        }

        // Push key onto stack.
        try ctx.interp.ctx.stack.push(key);

        // Execute SLOAD.
        try opSload(&ctx.interp);

        // Verify result.
        const result = try ctx.interp.ctx.stack.pop();
        try expectEqual(tc.expected_result, result);
    }
}

test "SLOAD: stack underflow error" {
    const ctx = try TestContext.create(testing.allocator);
    defer ctx.destroy();

    // Empty stack, should fail.
    try expectError(error.StackUnderflow, opSload(&ctx.interp));
}

test "SSTORE operations" {
    const test_cases = [_]struct {
        initial_value: ?U256,
        new_value: U256,
        expected_stored: U256,
    }{
        // Writes value to storage.
        .{
            .initial_value = null,
            .new_value = U256.fromU64(100),
            .expected_stored = U256.fromU64(100),
        },
        // Overwrites existing value.
        .{
            .initial_value = U256.fromU64(50),
            .new_value = U256.fromU64(200),
            .expected_stored = U256.fromU64(200),
        },
    };

    for (test_cases) |tc| {
        const ctx = try TestContext.create(testing.allocator);
        defer ctx.destroy();

        const key = U256.fromU64(42);

        // Set up initial storage if specified.
        if (tc.initial_value) |value| {
            try ctx.mock.setStorage(ctx.interp.ctx.contract.address, key, value);
        }

        // Push value first, then key (stack order: key on top).
        try ctx.interp.ctx.stack.push(tc.new_value);
        try ctx.interp.ctx.stack.push(key);

        // Execute SSTORE.
        try opSstore(&ctx.interp);

        // Verify value was written.
        const stored = ctx.mock.host().sload(ctx.interp.ctx.contract.address, key);
        try expectEqual(tc.expected_stored, stored);
    }
}

test "SSTORE: static call reverts" {
    const ctx = try TestContext.create(testing.allocator);
    defer ctx.destroy();

    // Set static context.
    ctx.interp.is_static = true;

    try ctx.interp.ctx.stack.push(U256.fromU64(100)); // value
    try ctx.interp.ctx.stack.push(U256.fromU64(1)); // key

    try expectError(error.StateWriteInStaticCall, opSstore(&ctx.interp));
}

test "SSTORE: stack underflow error" {
    const ctx = try TestContext.create(testing.allocator);
    defer ctx.destroy();

    // Only one item on stack (need two).
    try ctx.interp.ctx.stack.push(U256.fromU64(1));

    try expectError(error.StackUnderflow, opSstore(&ctx.interp));
}

test "SSTORE: gas <= CALL_STIPEND (2300) reverts" {
    const ctx = try TestContext.create(testing.allocator);
    defer ctx.destroy();

    // Set gas to exactly CALL_STIPEND (must be > 2300 to proceed).
    ctx.interp.gas.limit = ctx.interp.spec.call_stipend;
    ctx.interp.gas.used = 0;

    try ctx.interp.ctx.stack.push(U256.fromU64(100)); // value
    try ctx.interp.ctx.stack.push(U256.fromU64(1)); // key

    try expectError(error.OutOfGas, opSstore(&ctx.interp));
}

test "TLOAD operations" {
    const test_cases = [_]struct {
        initial_value: ?U256,
        expected_result: U256,
    }{
        // Reads transient value.
        .{
            .initial_value = U256.fromU64(100),
            .expected_result = U256.fromU64(100),
        },
        // Unset returns zero.
        .{
            .initial_value = null,
            .expected_result = U256.ZERO,
        },
    };

    for (test_cases) |tc| {
        const ctx = try TestContext.create(testing.allocator);
        defer ctx.destroy();

        const key = U256.fromU64(42);

        // Set up transient storage if initial value specified.
        if (tc.initial_value) |value| {
            ctx.mock.host().tstore(ctx.interp.ctx.contract.address, key, value);
        }

        // Push key onto stack.
        try ctx.interp.ctx.stack.push(key);

        // Execute TLOAD.
        try opTload(&ctx.interp);

        // Verify result.
        const result = try ctx.interp.ctx.stack.pop();
        try expectEqual(tc.expected_result, result);
    }
}

test "TSTORE: writes transient value" {
    const ctx = try TestContext.create(testing.allocator);
    defer ctx.destroy();

    const key = U256.fromU64(42);
    const value = U256.fromU64(100);

    // Push value first, then key (stack order: key on top).
    try ctx.interp.ctx.stack.push(value);
    try ctx.interp.ctx.stack.push(key);

    // Execute TSTORE.
    try opTstore(&ctx.interp);

    // Verify value was written to transient storage.
    const stored = ctx.mock.host().tload(ctx.interp.ctx.contract.address, key);
    try expectEqual(value, stored);
}

test "TSTORE: static call reverts" {
    const ctx = try TestContext.create(testing.allocator);
    defer ctx.destroy();

    // Set static context.
    ctx.interp.is_static = true;

    try ctx.interp.ctx.stack.push(U256.fromU64(100)); // value
    try ctx.interp.ctx.stack.push(U256.fromU64(1)); // key

    try expectError(error.StateWriteInStaticCall, opTstore(&ctx.interp));
}
