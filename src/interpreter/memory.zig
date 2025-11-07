const std = @import("std");
const Allocator = std.mem.Allocator;
const U256 = @import("../primitives/big.zig").U256;

/// EVM memory implementation.
///
/// Memory is a byte-addressable, dynamically expanding storage that exists only
/// for the duration of a message call. It is a pure data structure with no gas
/// tracking - gas calculations are handled by the Gas struct.
///
/// Properties:
/// - Byte-addressable (any offset can be accessed)
/// - Word-organized (operations work with 32-byte words)
/// - Automatically expands on access
/// - Always rounded to 32-byte boundaries (word alignment)
/// - Zero-initialized (all new bytes are 0)
/// - Volatile (destroyed at end of call context)
pub const Memory = struct {
    /// Dynamic byte array for memory storage.
    data: std.ArrayList(u8),

    /// Allocator for memory management.
    allocator: Allocator,

    const Self = @This();

    /// Memory operation errors.
    pub const Error = error{
        OutOfMemory,
        InvalidOffset,
        IntegerOverflow,
    };

    /// Initial capacity (128 words = 4096 bytes).
    pub const INITIAL_CAPACITY: usize = 4096;

    /// Maximum allowed memory size (128 MB).
    /// This provides defense-in-depth against overflow attacks and unrealistic allocations.
    pub const MAX_MEMORY_SIZE: usize = 128 * 1024 * 1024;

    /// Initialize a new memory instance.
    ///
    /// Pre-allocates capacity to avoid reallocations for typical usage.
    /// All memory starts at size 0, expanding on first access.
    pub fn init(allocator: Allocator) !Self {
        const data = try std.ArrayList(u8).initCapacity(allocator, INITIAL_CAPACITY);
        return Self{
            .data = data,
            .allocator = allocator,
        };
    }

    /// Free the memory's storage.
    pub fn deinit(self: *Self) void {
        self.data.deinit(self.allocator);
    }

    /// Get current memory size in bytes.
    pub fn len(self: *const Self) usize {
        return self.data.items.len;
    }

    /// Resize memory to at least the given size.
    ///
    /// Size is rounded up to next 32-byte (word) boundary per EVM spec.
    /// New bytes are zero-initialized as required by the EVM specification.
    ///
    /// This is an internal method - use ensureCapacity for operations.
    fn resize(self: *Self, new_size: usize) Error!void {
        const aligned_size = try alignToWord(new_size);
        if (aligned_size <= self.data.items.len) return;

        const old_len = self.data.items.len;
        try self.data.resize(self.allocator, aligned_size);

        // Zero-initialize new bytes (EVM requirement)
        @memset(self.data.items[old_len..], 0);
    }

    /// Ensure memory is large enough for operation at [offset..offset+size].
    ///
    /// Automatically expands memory if needed.
    /// Zero-size operations do not trigger expansion.
    pub fn ensureCapacity(self: *Self, offset: usize, size: usize) Error!void {
        if (size == 0) return;

        const end = try checkedAdd(offset, size);

        // Enforce maximum memory size
        if (end > MAX_MEMORY_SIZE) return error.InvalidOffset;

        if (end > self.data.items.len) {
            try self.resize(end);
        }
    }

    /// Load a 32-byte word from memory at the given offset (MLOAD).
    ///
    /// Automatically expands memory if needed.
    ///
    /// Note: Caller must handle gas calculation before calling this method.
    pub fn mload(self: *Self, offset: usize) Error!U256 {
        try self.ensureCapacity(offset, 32);
        const bytes = self.data.items[offset..][0..32];
        return U256.fromBeBytes(bytes);
    }

    /// Store a 32-byte word to memory at the given offset (MSTORE).
    ///
    /// Automatically expands memory if needed.
    ///
    /// Note: Caller must handle gas calculation before calling this method.
    pub fn mstore(self: *Self, offset: usize, value: U256) Error!void {
        try self.ensureCapacity(offset, 32);
        const bytes = value.toBeBytes();
        @memcpy(self.data.items[offset..][0..32], &bytes);
    }

    /// Store a single byte to memory at the given offset (MSTORE8).
    ///
    /// Automatically expands memory if needed.
    /// Only the lowest 8 bits of the value are used.
    ///
    /// Note: Caller must handle gas calculation before calling this method.
    pub fn mstore8(self: *Self, offset: usize, value: u8) Error!void {
        try self.ensureCapacity(offset, 1);
        self.data.items[offset] = value;
    }

    /// Get a slice view of memory [offset..offset+size].
    ///
    /// Does NOT expand memory. Returns error if range is out of bounds.
    /// Used for zero-copy operations like CALLDATACOPY, RETURN, etc.
    ///
    /// The returned slice is valid until the next memory modification.
    pub fn getSlice(self: *const Self, offset: usize, size: usize) Error![]const u8 {
        const end = try checkedAdd(offset, size);

        if (end > self.data.items.len) {
            return error.InvalidOffset;
        }
        return self.data.items[offset..][0..size];
    }

    /// Get a mutable slice view of memory [offset..offset+size].
    ///
    /// Does NOT expand memory. Returns error if range is out of bounds.
    /// Used for operations that write directly to memory (CALLDATACOPY, etc.).
    ///
    /// The returned slice is valid until the next memory modification.
    pub fn getSliceMut(self: *Self, offset: usize, size: usize) Error![]u8 {
        const end = try checkedAdd(offset, size);

        if (end > self.data.items.len) {
            return error.InvalidOffset;
        }
        return self.data.items[offset..][0..size];
    }

    /// Copy data into memory at [offset..offset+bytes.len].
    ///
    /// Automatically expands memory if needed.
    ///
    /// Note: Caller must handle gas calculation before calling this method.
    pub fn set(self: *Self, offset: usize, bytes: []const u8) Error!void {
        if (bytes.len == 0) return;
        try self.ensureCapacity(offset, bytes.len);
        @memcpy(self.data.items[offset..][0..bytes.len], bytes);
    }

    /// Copy data from memory into a buffer.
    ///
    /// Returns error if range is out of bounds.
    pub fn copy(self: *const Self, offset: usize, dest: []u8) Error!void {
        const end = try checkedAdd(offset, dest.len);

        if (end > self.data.items.len) {
            return error.InvalidOffset;
        }
        @memcpy(dest, self.data.items[offset..][0..dest.len]);
    }
};

/// Round size up to next 32-byte boundary.
///
/// This is required by the EVM spec for memory expansion.
fn alignToWord(size: usize) Memory.Error!usize {
    const with_padding = try checkedAdd(size, 31);
    const words = with_padding / 32;
    return try checkedMul(words, 32);
}

/// Checked addition with overflow detection.
inline fn checkedAdd(a: usize, b: usize) Memory.Error!usize {
    const result = @addWithOverflow(a, b);
    if (result[1] == 1) return error.IntegerOverflow;
    return result[0];
}

/// Checked multiplication with overflow detection.
inline fn checkedMul(a: usize, b: usize) Memory.Error!usize {
    const result = @mulWithOverflow(a, b);
    if (result[1] == 1) return error.IntegerOverflow;
    return result[0];
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Memory: init and deinit" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try expectEqual(0, memory.len());
}

test "Memory: mstore and mload single word" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    const value = U256.fromU64(0x123456789abcdef0);
    try memory.mstore(0, value);

    try expectEqual(32, memory.len());

    const loaded = try memory.mload(0);
    try expect(value.eql(loaded));
}

test "Memory: mstore8 single byte" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.mstore8(0, 0x42);
    try expectEqual(32, memory.len()); // Aligned to word

    const slice = try memory.getSlice(0, 1);
    try expectEqual(0x42, slice[0]);
}

test "Memory: automatic expansion" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.mstore(100, U256.fromU64(42));

    // Should expand to at least 132 bytes (100 + 32)
    // Aligned to 32: ceil(132/32) * 32 = 160 bytes
    try expectEqual(160, memory.len());
}

test "Memory: zero-initialization" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.mstore(32, U256.fromU64(1));
    try expectEqual(64, memory.len());

    // First word should be zero (never written)
    const first = try memory.mload(0);
    try expect(U256.ZERO.eql(first));
}

test "Memory: word alignment on resize" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Request 33 bytes (should round to 64)
    try memory.resize(33);
    try expectEqual(64, memory.len());

    // Request 65 bytes (should round to 96)
    try memory.resize(65);
    try expectEqual(96, memory.len());
}

test "Memory: non-aligned access (mload)" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.mstore(0, U256.fromU64(0x1111111111111111));
    try memory.mstore(32, U256.fromU64(0x2222222222222222));

    // Load from offset 16 (crosses word boundary)
    const value = try memory.mload(16);
    const expected = U256{ .limbs = .{ 0, 0, 0x1111111111111111, 0 } };
    try expect(expected.eql(value));
}

test "Memory: mstore8 at any offset" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Write bytes at arbitrary offsets
    try memory.mstore8(7, 0xAA);
    try memory.mstore8(15, 0xBB);
    try memory.mstore8(31, 0xCC);

    const slice = try memory.getSlice(0, 32);
    try expectEqual(0xAA, slice[7]);
    try expectEqual(0xBB, slice[15]);
    try expectEqual(0xCC, slice[31]);

    // Other bytes should be zero
    try expectEqual(0, slice[0]);
    try expectEqual(0, slice[6]);
    try expectEqual(0, slice[8]);
}

test "Memory: set and getSlice" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    const data = [_]u8{ 1, 2, 3, 4, 5 };
    try memory.set(10, &data);

    // Memory should be at least 15 bytes, aligned to 32
    try expectEqual(32, memory.len());

    const slice = try memory.getSlice(10, 5);
    try expectEqual(5, slice.len);
    try expectEqual(1, slice[0]);
    try expectEqual(5, slice[4]);
}

test "Memory: getSlice out of bounds" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.resize(32);

    // Try to read beyond current size
    try expectError(error.InvalidOffset, memory.getSlice(20, 20));
}

test "Memory: copy data out" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.mstore(0, U256.fromU64(0x123456789abcdef0));

    var buffer: [32]u8 = undefined;
    try memory.copy(0, &buffer);

    // Verify the value was copied correctly (big-endian, U64 in U256 is right-aligned)
    try expectEqual(0xf0, buffer[31]); // LSB at end
    try expectEqual(0xde, buffer[30]);
    try expectEqual(0xbc, buffer[29]);
}

test "Memory: zero-size operations" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Zero-size operations should be no-ops
    try memory.set(100, &[_]u8{});
    try expectEqual(0, memory.len());

    try memory.ensureCapacity(100, 0);
    try expectEqual(0, memory.len());
}

test "Memory: large offset" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Large offset should succeed (up to memory limits)
    const large_offset = 1024 * 1024; // 1MB
    try memory.mstore8(large_offset, 0xFF);

    const slice = try memory.getSlice(large_offset, 1);
    try expectEqual(0xFF, slice[0]);
}

test "Memory: overlapping operations" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Set bytes [0..10]
    const data1 = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    try memory.set(0, &data1);

    // Overwrite bytes [5..15] (overlaps)
    const data2 = [_]u8{ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 };
    try memory.set(5, &data2);

    // Check results
    const slice = try memory.getSlice(0, 20);
    try expectEqual(1, slice[0]); // Original
    try expectEqual(5, slice[4]); // Original
    try expectEqual(11, slice[5]); // Overwritten
    try expectEqual(20, slice[14]); // New
}

test "Memory: getSliceMut allows modification" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Allocate 32 bytes
    try memory.ensureCapacity(0, 32);

    // Get mutable slice and modify
    var slice = try memory.getSliceMut(0, 32);
    slice[0] = 0xAA;
    slice[31] = 0xBB;

    // Verify modifications
    const read_slice = try memory.getSlice(0, 32);
    try expectEqual(0xAA, read_slice[0]);
    try expectEqual(0xBB, read_slice[31]);
}

test "Memory: U256 big-endian serialization" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Store max U256
    const max = U256.MAX;
    try memory.mstore(0, max);

    // All bytes should be 0xFF
    const slice = try memory.getSlice(0, 32);
    for (slice) |byte| {
        try expectEqual(0xFF, byte);
    }

    // Load back
    const loaded = try memory.mload(0);
    try expect(max.eql(loaded));
}

test "Memory: U256 zero padding" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Store small value
    const small = U256.fromU64(0x42);
    try memory.mstore(0, small);

    // Most significant bytes should be zero (big-endian)
    const slice = try memory.getSlice(0, 32);
    for (slice[0..31]) |byte| {
        try expectEqual(0, byte);
    }
    try expectEqual(0x42, slice[31]);
}

test "Memory: ensureCapacity overflow protection" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test offset + size overflow
    const huge_offset = std.math.maxInt(usize) - 10;
    try expectError(error.IntegerOverflow, memory.ensureCapacity(huge_offset, 20));

    // Test exact overflow boundary
    try expectError(error.IntegerOverflow, memory.ensureCapacity(std.math.maxInt(usize), 1));

    // Test with both values large
    const large1 = std.math.maxInt(usize) / 2 + 1;
    try expectError(error.IntegerOverflow, memory.ensureCapacity(large1, large1));
}

test "Memory: ensureCapacity MAX_MEMORY_SIZE enforcement" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Test exceeding MAX_MEMORY_SIZE
    const too_large = Memory.MAX_MEMORY_SIZE + 1;
    try expectError(error.InvalidOffset, memory.ensureCapacity(0, too_large));

    // Test offset + size exceeding MAX_MEMORY_SIZE
    const offset = Memory.MAX_MEMORY_SIZE - 10;
    try expectError(error.InvalidOffset, memory.ensureCapacity(offset, 20));
}

test "Memory: getSlice overflow protection" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Allocate some memory first
    try memory.ensureCapacity(0, 64);

    // Test offset + size overflow
    const huge_offset = std.math.maxInt(usize) - 10;
    try expectError(error.IntegerOverflow, memory.getSlice(huge_offset, 20));

    // Test exact overflow boundary
    try expectError(error.IntegerOverflow, memory.getSlice(std.math.maxInt(usize), 1));
}

test "Memory: getSliceMut overflow protection" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Allocate some memory first
    try memory.ensureCapacity(0, 64);

    // Test offset + size overflow
    const huge_offset = std.math.maxInt(usize) - 10;
    try expectError(error.IntegerOverflow, memory.getSliceMut(huge_offset, 20));

    // Test exact overflow boundary
    try expectError(error.IntegerOverflow, memory.getSliceMut(std.math.maxInt(usize), 1));
}

test "Memory: copy overflow protection" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Allocate some memory first
    try memory.ensureCapacity(0, 64);

    var buffer: [20]u8 = undefined;

    // Test offset + dest.len overflow
    const huge_offset = std.math.maxInt(usize) - 10;
    try expectError(error.IntegerOverflow, memory.copy(huge_offset, &buffer));

    // Test exact overflow boundary
    var single_byte: [1]u8 = undefined;
    try expectError(error.IntegerOverflow, memory.copy(std.math.maxInt(usize), &single_byte));
}

test "Memory: alignToWord overflow protection on addition" {
    // Test size + 31 overflow
    const huge_size = std.math.maxInt(usize) - 10;
    try expectError(error.IntegerOverflow, alignToWord(huge_size));

    // Test exact overflow boundary
    try expectError(error.IntegerOverflow, alignToWord(std.math.maxInt(usize)));
    try expectError(error.IntegerOverflow, alignToWord(std.math.maxInt(usize) - 30));
}

test "Memory: legitimate large operations still work" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Large but valid offset (1MB)
    const large_valid_offset: usize = 1024 * 1024;

    // Should succeed - well below MAX_MEMORY_SIZE
    try memory.ensureCapacity(large_valid_offset, 32);
    try expectEqual(1024 * 1024 + 32, memory.len());

    // Should be able to write and read
    try memory.mstore(large_valid_offset, U256.fromU64(0xDEADBEEF));
    const value = try memory.mload(large_valid_offset);
    try expect(U256.fromU64(0xDEADBEEF).eql(value));
}

test "Memory: edge case - zero size with huge offset" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    // Zero-size operations should not trigger overflow checks
    const huge_offset = std.math.maxInt(usize) - 10;

    // This should be a no-op and not error
    try memory.ensureCapacity(huge_offset, 0);

    // Memory should remain empty
    try expectEqual(0, memory.len());
}

test "Memory: set overflow protection via ensureCapacity" {
    var memory = try Memory.init(std.testing.allocator);
    defer memory.deinit();

    const data = [_]u8{ 1, 2, 3, 4, 5 };

    // Test offset + size overflow
    const huge_offset = std.math.maxInt(usize) - 2;
    try expectError(error.IntegerOverflow, memory.set(huge_offset, &data));
}
