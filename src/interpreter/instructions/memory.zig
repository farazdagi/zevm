//! Memory operations instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Stack = @import("../stack.zig").Stack;
const Memory = @import("../memory.zig").Memory;

/// Load word from memory (MLOAD).
///
/// Stack: [offset, ...] -> [value, ...]
/// Gas is charged in interpreter before calling this function.
pub inline fn opMload(stack: *Stack, memory: *Memory) !void {
    const offset_ptr = try stack.peekMut(0);
    const offset = offset_ptr.toUsize() orelse return error.InvalidOffset;

    offset_ptr.* = try memory.mload(offset);
}

/// Store word to memory (MSTORE).
///
/// Stack: [offset, value, ...] -> [...]
/// Gas is charged in interpreter before calling this function.
pub inline fn opMstore(stack: *Stack, memory: *Memory) !void {
    const offset_u256 = try stack.pop();
    const value = try stack.pop();
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;

    try memory.mstore(offset, value);
}

/// Store byte to memory (MSTORE8).
///
/// Stack: [offset, value, ...] -> [...]
/// Gas is charged in interpreter before calling this function.
pub inline fn opMstore8(stack: *Stack, memory: *Memory) !void {
    const offset_u256 = try stack.pop();
    const value_u256 = try stack.pop();
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;

    // Extract least significant byte
    const byte: u8 = @truncate(value_u256.toU64() orelse 0);

    try memory.mstore8(offset, byte);
}

/// Get size of active memory in bytes (MSIZE).
///
/// Stack: [...] -> [size, ...]
pub inline fn opMsize(stack: *Stack, memory: *const Memory) !void {
    const size = memory.len();
    try stack.push(U256.fromU64(size));
}

/// Copy memory (MCOPY) - EIP-5656.
///
/// Stack: [..., dest_offset, src_offset, length] -> [...]
pub inline fn opMcopy(stack: *Stack, memory: *Memory) !void {
    _ = stack;
    _ = memory;
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "memory: smoke test" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test MSTORE + MLOAD
    // Stack for MSTORE: [offset, value, ...] where offset is top
    try stack.push(U256.fromU64(0x42)); // value (will be second)
    try stack.push(U256.fromU64(0)); // offset (will be top)
    try opMstore(&stack, &memory);

    // Stack for MLOAD: [offset, ...] where offset is top
    try stack.push(U256.fromU64(0)); // offset
    try opMload(&stack, &memory);
    const loaded = try stack.pop();
    try expectEqual(U256.fromU64(0x42), loaded);

    // Test MSIZE
    try opMsize(&stack, &memory);
    const size = try stack.pop();
    try expectEqual(U256.fromU64(32), size); // Should be word-aligned

    // Test MSTORE8
    // Stack for MSTORE8: [offset, value, ...] where offset is top
    try stack.push(U256.fromU64(0xFF)); // value (will be second)
    try stack.push(U256.fromU64(5)); // offset (will be top)
    try opMstore8(&stack, &memory);

    // MCOPY still unimplemented
    try stack.push(U256.fromU64(32));
    try stack.push(U256.ZERO);
    try stack.push(U256.ZERO);
    try expectError(error.UnimplementedOpcode, opMcopy(&stack, &memory));
}

test "MLOAD: basic ops" {
    const test_cases = [_]struct {
        offset: u64,
        stored_value: U256,
        expected: U256,
    }{
        .{ .offset = 0, .stored_value = U256.fromU64(0x42), .expected = U256.fromU64(0x42) },
        .{ .offset = 32, .stored_value = U256.MAX, .expected = U256.MAX },
        .{ .offset = 64, .stored_value = U256.ZERO, .expected = U256.ZERO },
        .{ .offset = 96, .stored_value = U256.fromU64(0x123456789ABCDEF), .expected = U256.fromU64(0x123456789ABCDEF) },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var memory = try Memory.init(std.testing.allocator);
        defer memory.deinit();

        // Pre-store value
        try memory.mstore(tc.offset, tc.stored_value);

        // Execute MLOAD
        try stack.push(U256.fromU64(tc.offset));
        try opMload(&stack, &memory);

        const result = try stack.pop();
        try expectEqual(tc.expected, result);
    }
}

test "MLOAD: load from uninitialized memory" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Load from uninitialized memory (memory auto-expands and zero-fills)
    try stack.push(U256.fromU64(128));
    try opMload(&stack, &memory);

    // Ensure that load returns zeroed value.
    const result = try stack.pop();
    try expectEqual(U256.ZERO, result);
}

test "MSTORE: basic ops" {
    const test_cases = [_]struct {
        offset: u64,
        value: U256,
    }{
        .{ .offset = 0, .value = U256.fromU64(0x1234) },
        .{ .offset = 32, .value = U256.MAX },
        .{ .offset = 64, .value = U256.ZERO },
        .{ .offset = 128, .value = U256.fromU64(0xDEADBEEF) },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var memory = try Memory.init(std.testing.allocator);
        defer memory.deinit();

        // Execute MSTORE
        try stack.push(tc.value);
        try stack.push(U256.fromU64(tc.offset));
        try opMstore(&stack, &memory);

        // Verify stored value
        const loaded = try memory.mload(tc.offset);
        try expectEqual(tc.value, loaded);
    }
}

test "MSTORE: memory expansion" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Initially empty
    try expectEqual(0, memory.len());

    // Store at offset 0 (expands to 32 bytes)
    try expectEqual(0, memory.len());
    try stack.push(U256.fromU64(0x42));
    try stack.push(U256.fromU64(0));
    try opMstore(&stack, &memory);
    try expectEqual(32, memory.len());

    // Store at offset 64 (expands to 96 bytes)
    try stack.push(U256.fromU64(0x99));
    try stack.push(U256.fromU64(64));
    try opMstore(&stack, &memory);
    try expectEqual(96, memory.len());
}

test "MSTORE: non-aligned expansion" {
    const test_cases = [_]struct {
        offset: u64,
        expected_size: u64, // Memory should expand to next word boundary
    }{
        .{ .offset = 17, .expected_size = 64 }, // 17 + 32 = 49 -> rounds up to 64
        .{ .offset = 50, .expected_size = 96 }, // 50 + 32 = 82 -> rounds up to 96
        .{ .offset = 95, .expected_size = 128 }, // 95 + 32 = 127 -> rounds up to 128
        .{ .offset = 1, .expected_size = 64 }, // 1 + 32 = 33 -> rounds up to 64
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var memory = try Memory.init(std.testing.allocator);
        defer memory.deinit();

        // Store at non-aligned offset
        try stack.push(U256.fromU64(0xABCD));
        try stack.push(U256.fromU64(tc.offset));
        try opMstore(&stack, &memory);

        // Verify memory expands to word boundary
        try expectEqual(tc.expected_size, memory.len());
    }
}

test "MSTORE8: byte storage" {
    const test_cases = [_]struct {
        offset: u64,
        value: u64, // Full value (only LSB stored)
        expected_byte: u8,
    }{
        .{ .offset = 0, .value = 0x42, .expected_byte = 0x42 },
        .{ .offset = 1, .value = 0xFF, .expected_byte = 0xFF },
        .{ .offset = 2, .value = 0x1234, .expected_byte = 0x34 }, // Only LSB
        .{ .offset = 5, .value = 0xABCDEF12, .expected_byte = 0x12 },
        .{ .offset = 10, .value = 0x00, .expected_byte = 0x00 },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var memory = try Memory.init(std.testing.allocator);
        defer memory.deinit();

        // Execute MSTORE8
        try stack.push(U256.fromU64(tc.value));
        try stack.push(U256.fromU64(tc.offset));
        try opMstore8(&stack, &memory);

        // Verify stored byte by loading the word containing it
        const word_offset = (tc.offset / 32) * 32;
        const loaded_word = try memory.mload(word_offset);
        const loaded_bytes = loaded_word.toBeBytes();
        const byte_in_word = tc.offset % 32;

        try expectEqual(tc.expected_byte, loaded_bytes[byte_in_word]);
    }
}

test "MSIZE: memory size tracking" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Initially empty
    try opMsize(&stack, &memory);
    try expectEqual(0, (try stack.pop()).toU64().?);

    // After storing at offset 0 (expands to 32 bytes)
    try memory.mstore(0, U256.fromU64(0x42));
    try opMsize(&stack, &memory);
    try expectEqual(32, (try stack.pop()).toU64().?);

    // After storing at offset 64 (expands to 96 bytes)
    try memory.mstore(64, U256.fromU64(0x99));
    try opMsize(&stack, &memory);
    try expectEqual(96, (try stack.pop()).toU64().?);

    // MSIZE doesn't change memory size
    try opMsize(&stack, &memory);
    try expectEqual(96, (try stack.pop()).toU64().?);
    try expectEqual(96, memory.len());
}

test "MSIZE: word alignment" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Store single byte at offset 5
    try memory.mstore8(5, 0xFF);

    // Memory should be word-aligned (32 bytes)
    try opMsize(&stack, &memory);
    try expectEqual(32, (try stack.pop()).toU64().?);
}

test "memory: error cases" {
    const test_cases = [_]struct {
        values_to_push: []const u64,
        op: enum { mload, mstore, mstore8 },
        expected_error: anyerror,
    }{
        .{ .values_to_push = &.{}, .op = .mload, .expected_error = error.StackUnderflow },
        .{ .values_to_push = &.{}, .op = .mstore, .expected_error = error.StackUnderflow },
        .{ .values_to_push = &.{0x42}, .op = .mstore, .expected_error = error.StackUnderflow },
        .{ .values_to_push = &.{}, .op = .mstore8, .expected_error = error.StackUnderflow },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var memory = try Memory.init(std.testing.allocator);
        defer memory.deinit();

        for (tc.values_to_push) |val| {
            try stack.push(U256.fromU64(val));
        }

        switch (tc.op) {
            .mload => try expectError(tc.expected_error, opMload(&stack, &memory)),
            .mstore => try expectError(tc.expected_error, opMstore(&stack, &memory)),
            .mstore8 => try expectError(tc.expected_error, opMstore8(&stack, &memory)),
        }
    }
}
