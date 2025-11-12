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

/// Copy memory (MCOPY) - EIP-5656, Cancun+.
///
/// Stack: [dest_offset, src_offset, length, ...] -> [...]
/// Copies length bytes from src_offset to dest_offset within memory.
/// Handles overlapping regions correctly (memmove semantics).
/// Gas is charged in interpreter before calling this function.
pub inline fn opMcopy(stack: *Stack, memory: *Memory) !void {
    // Pop operands (dest first per EVM stack convention)
    const dest_u256 = try stack.pop();
    const src_u256 = try stack.pop();
    const length_u256 = try stack.pop();

    // Convert to usize with overflow check.
    const dest = dest_u256.toUsize() orelse return error.InvalidOffset;
    const src = src_u256.toUsize() orelse return error.InvalidOffset;
    const length = length_u256.toUsize() orelse return error.InvalidOffset;

    // Handle zero-length case (no-op).
    if (length == 0) return;

    // Calculate end positions with overflow check
    const dest_end = std.math.add(usize, dest, length) catch return error.InvalidOffset;
    const src_end = std.math.add(usize, src, length) catch return error.InvalidOffset;

    // Ensure memory is large enough for both source and destination
    const max_end = @max(dest_end, src_end);
    try memory.ensureCapacity(0, max_end);

    // Copy with memmove semantics to handle overlapping regions
    // std.mem.copyForwards and copyBackwards handle overlapping correctly
    const mem_slice = memory.data.items;
    if (dest <= src) {
        // Copy forwards (safe for dest < src or no overlap)
        std.mem.copyForwards(u8, mem_slice[dest..dest_end], mem_slice[src..src_end]);
    } else {
        // Copy backwards (safe for dest > src to avoid overwriting source)
        std.mem.copyBackwards(u8, mem_slice[dest..dest_end], mem_slice[src..src_end]);
    }
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

    // Test MCOPY - copy first word to second word position
    // First, store a value in memory
    try stack.push(U256.fromU64(0xDEADBEEF));
    try stack.push(U256.fromU64(0));
    try opMstore(&stack, &memory);

    // Copy from offset 0 to offset 32 for 32 bytes
    // Stack: [dest, src, length]
    try stack.push(U256.fromU64(32)); // length
    try stack.push(U256.fromU64(0)); // src
    try stack.push(U256.fromU64(32)); // dest
    try opMcopy(&stack, &memory);

    // Verify the copy
    try stack.push(U256.fromU64(32)); // offset
    try opMload(&stack, &memory);
    const copied = try stack.pop();
    try expectEqual(U256.fromU64(0xDEADBEEF), copied);
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

test "MCOPY: basic copy operations" {
    const test_cases = [_]struct {
        dest: u64,
        src: u64,
        length: u64,
        src_value: U256,
    }{
        .{
            // Copy word forward.
            .dest = 32,
            .src = 0,
            .length = 32,
            .src_value = U256.fromU64(0x1234),
        },
        .{
            // Copy word backward.
            .dest = 0,
            .src = 32,
            .length = 32,
            .src_value = U256.fromU64(0xABCD),
        },
        .{
            // Copy max value.
            .dest = 96,
            .src = 64,
            .length = 32,
            .src_value = U256.MAX,
        },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var memory = try Memory.init(std.testing.allocator);
        defer memory.deinit();

        // Setup: store value at source offset
        try memory.mstore(tc.src, tc.src_value);

        // Execute MCOPY: [dest, src, length]
        try stack.push(U256.fromU64(tc.length));
        try stack.push(U256.fromU64(tc.src));
        try stack.push(U256.fromU64(tc.dest));
        try opMcopy(&stack, &memory);

        // Verify: load from destination and compare
        const loaded = try memory.mload(tc.dest);
        try expectEqual(tc.src_value, loaded);

        // Ensure source is unchanged
        const src_still = try memory.mload(tc.src);
        try expectEqual(tc.src_value, src_still);
    }
}

test "MCOPY: partial word copy" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Setup: Store a distinctive byte pattern at offset 0
    try memory.mstore8(0, 0xAA);
    try memory.mstore8(1, 0xBB);
    try memory.mstore8(2, 0xCC);
    try memory.mstore8(3, 0xDD);

    // Copy 4 bytes from offset 0 to offset 32
    try stack.push(U256.fromU64(4)); // length
    try stack.push(U256.fromU64(0)); // src
    try stack.push(U256.fromU64(32)); // dest
    try opMcopy(&stack, &memory);

    // Verify: Check that the 4 bytes were copied correctly
    const slice = try memory.getSlice(32, 4);
    try expectEqual(0xAA, slice[0]);
    try expectEqual(0xBB, slice[1]);
    try expectEqual(0xCC, slice[2]);
    try expectEqual(0xDD, slice[3]);
}

test "MCOPY: overlapping regions forward" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Setup: Store pattern [0xAA, 0xBB, 0xCC, 0xDD] at offset 0
    try memory.mstore8(0, 0xAA);
    try memory.mstore8(1, 0xBB);
    try memory.mstore8(2, 0xCC);
    try memory.mstore8(3, 0xDD);

    // Copy from offset 0 to offset 2 (overlapping, forward)
    // This should copy [0xAA, 0xBB] to positions [2, 3]
    // Result: [0xAA, 0xBB, 0xAA, 0xBB]
    try stack.push(U256.fromU64(2)); // length
    try stack.push(U256.fromU64(0)); // src
    try stack.push(U256.fromU64(2)); // dest
    try opMcopy(&stack, &memory);

    // Verify the copy
    const slice = try memory.getSlice(0, 4);
    try expectEqual(0xAA, slice[0]);
    try expectEqual(0xBB, slice[1]);
    try expectEqual(0xAA, slice[2]);
    try expectEqual(0xBB, slice[3]);
}

test "MCOPY: overlapping regions backward" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Setup: Store pattern [0xAA, 0xBB, 0xCC, 0xDD] at offset 2
    try memory.mstore8(2, 0xAA);
    try memory.mstore8(3, 0xBB);
    try memory.mstore8(4, 0xCC);
    try memory.mstore8(5, 0xDD);

    // Copy from offset 2 to offset 0 (overlapping, backward)
    // This should copy [0xAA, 0xBB, 0xCC, 0xDD] to positions [0, 1, 2, 3]
    try stack.push(U256.fromU64(4)); // length
    try stack.push(U256.fromU64(2)); // src
    try stack.push(U256.fromU64(0)); // dest
    try opMcopy(&stack, &memory);

    // Verify the copy
    const slice = try memory.getSlice(0, 6);
    try expectEqual(0xAA, slice[0]);
    try expectEqual(0xBB, slice[1]);
    try expectEqual(0xCC, slice[2]);
    try expectEqual(0xDD, slice[3]);
}

test "MCOPY: zero-length copy" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Store value at offset 0
    try memory.mstore(0, U256.fromU64(0x42));
    const initial_size = memory.len();

    // Zero-length copy should be no-op
    try stack.push(U256.ZERO); // length = 0
    try stack.push(U256.fromU64(0)); // src
    try stack.push(U256.fromU64(32)); // dest
    try opMcopy(&stack, &memory);

    // Memory size should not change
    try expectEqual(initial_size, memory.len());

    // Original value should be unchanged
    const value = try memory.mload(0);
    try expectEqual(U256.fromU64(0x42), value);
}

test "MCOPY: memory expansion" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Store value at offset 0
    try memory.mstore(0, U256.fromU64(0xBEEF));
    try expectEqual(32, memory.len());

    // Copy to far offset (should expand memory)
    try stack.push(U256.fromU64(32)); // length
    try stack.push(U256.fromU64(0)); // src
    try stack.push(U256.fromU64(256)); // dest (far offset)
    try opMcopy(&stack, &memory);

    // Memory should expand to accommodate destination
    try expect(memory.len() >= 256 + 32);

    // Verify copied value
    const copied = try memory.mload(256);
    try expectEqual(U256.fromU64(0xBEEF), copied);
}

test "MCOPY: large copy" {
    var stack = try Stack.init(std.testing.allocator);
    defer stack.deinit();

    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Fill 5 words with different values
    try memory.mstore(0, U256.fromU64(0x1111));
    try memory.mstore(32, U256.fromU64(0x2222));
    try memory.mstore(64, U256.fromU64(0x3333));
    try memory.mstore(96, U256.fromU64(0x4444));
    try memory.mstore(128, U256.fromU64(0x5555));

    // Copy 160 bytes (5 words) from offset 0 to offset 200
    try stack.push(U256.fromU64(160)); // length
    try stack.push(U256.fromU64(0)); // src
    try stack.push(U256.fromU64(200)); // dest
    try opMcopy(&stack, &memory);

    // Verify all values copied correctly
    try expectEqual(U256.fromU64(0x1111), try memory.mload(200));
    try expectEqual(U256.fromU64(0x2222), try memory.mload(232));
    try expectEqual(U256.fromU64(0x3333), try memory.mload(264));
    try expectEqual(U256.fromU64(0x4444), try memory.mload(296));
    try expectEqual(U256.fromU64(0x5555), try memory.mload(328));
}

test "MCOPY: EIP-5656 official test cases" {
    const TestCase = struct {
        dst: usize,
        src: usize,
        length: usize,
        // Initial memory setup as byte patterns
        setup: []const u8,
        setup_offset: usize,
        // Expected memory bytes after MCOPY
        expected: []const u8,
        expected_offset: usize,
    };

    const test_cases = [_]TestCase{
        // Test Case 1: Basic forward copy (non-overlapping)
        .{
            .dst = 0,
            .src = 32,
            .length = 32,
            .setup = &[_]u8{
                0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
                0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
                0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
            },
            .setup_offset = 32,
            .expected = &[_]u8{
                0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
                0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
                0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
            },
            .expected_offset = 0,
        },
        // Test Case 2: Self-copy (identity - dst == src)
        .{
            .dst = 0,
            .src = 0,
            .length = 32,
            .setup = &[_]u8{
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
            },
            .setup_offset = 0,
            .expected = &[_]u8{
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
            },
            .expected_offset = 0,
        },
        // Test Case 3: Overlapping copy - forward (dst < src, regions overlap)
        .{
            .dst = 0,
            .src = 1,
            .length = 8,
            .setup = &[_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 },
            .setup_offset = 0,
            .expected = &[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 },
            .expected_offset = 0,
        },
        // Test Case 4: Overlapping copy - backward (dst > src, regions overlap)
        .{
            .dst = 1,
            .src = 0,
            .length = 8,
            .setup = &[_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 },
            .setup_offset = 0,
            .expected = &[_]u8{ 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07 },
            .expected_offset = 0,
        },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var memory = try Memory.init(std.testing.allocator);
        defer memory.deinit();

        // Setup: Write initial memory pattern
        for (tc.setup, 0..) |byte, i| {
            try memory.mstore8(tc.setup_offset + i, byte);
        }

        // Execute MCOPY: [dest, src, length]
        try stack.push(U256.fromU64(@intCast(tc.length)));
        try stack.push(U256.fromU64(@intCast(tc.src)));
        try stack.push(U256.fromU64(@intCast(tc.dst)));
        try opMcopy(&stack, &memory);

        // Verify: Check byte-by-byte that result matches expected
        const result = try memory.getSlice(tc.expected_offset, tc.expected.len);
        for (tc.expected, 0..) |expected_byte, i| {
            try expectEqual(expected_byte, result[i]);
        }
    }
}

test "MCOPY: error cases" {
    const test_cases = [_]struct {
        dest: U256,
        src: U256,
        length: U256,
        expected_error: anyerror,
        description: []const u8,
    }{
        // Stack underflow cases
        .{ .dest = U256.ZERO, .src = U256.ZERO, .length = U256.ZERO, .expected_error = error.StackUnderflow, .description = "Empty stack" },
    };

    for (test_cases) |tc| {
        var stack = try Stack.init(std.testing.allocator);
        defer stack.deinit();

        var memory = try Memory.init(std.testing.allocator);
        defer memory.deinit();

        // For stack underflow test, don't push anything
        if (tc.expected_error == error.StackUnderflow) {
            try expectError(tc.expected_error, opMcopy(&stack, &memory));
            continue;
        }

        // For other tests, push the values
        try stack.push(tc.length);
        try stack.push(tc.src);
        try stack.push(tc.dest);
        try expectError(tc.expected_error, opMcopy(&stack, &memory));
    }
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
