const std = @import("std");

/// 32-byte fixed bytes (256 bits)
///
/// Commonly used for:
/// - Keccak-256 hashes
/// - Storage slots
/// - EVM word size (256 bits)
/// - Transaction hashes
/// - Block hashes
pub const B256 = FixedBytes(32);

/// 20-byte fixed bytes (160 bits)
///
/// Note: For Ethereum addresses, use the dedicated `Address` type which is a wrapper
/// around `B160` and includes address-specific utilities such as EIP-55 checksumming.
pub const B160 = FixedBytes(20);

/// Fixed-size byte array errors
pub const FixedBytesError = error{
    InvalidHexStringLength,
    InvalidHexDigit,
    InvalidSliceLength,
    BufferTooSmall,
};

/// Generic fixed-size byte array
pub fn FixedBytes(comptime size: usize) type {
    return struct {
        bytes: [size]u8,

        const Self = @This();

        /// The size of this fixed bytes array
        pub const len = size;

        /// Initialize from a byte array
        pub fn init(bytes: [size]u8) Self {
            return Self{ .bytes = bytes };
        }

        /// Create a zero-filled fixed bytes array
        pub fn zero() Self {
            return Self{ .bytes = [_]u8{0} ** size };
        }

        /// Create a fixed bytes array filled with a repeated byte value
        pub fn repeat(byte: u8) Self {
            return Self{ .bytes = [_]u8{byte} ** size };
        }

        /// Parse from a hex string (run-time)
        ///
        /// Accepts hex strings with or without "0x" prefix.
        /// Pair of hex digits represents a byte, so expected length of the
        /// input hex is `size*2` (+2 for "0x", if present).
        pub fn fromHex(hex: []const u8) FixedBytesError!Self {
            // Check for "0x" prefix
            const has_prefix = hex.len >= 2 and hex[0] == '0' and hex[1] == 'x';

            // Validate length
            const expected_len = size * 2 + if (has_prefix) 2 else @as(usize, 0);
            if (hex.len != expected_len)
                return FixedBytesError.InvalidHexStringLength;

            const hex_digits = if (has_prefix) hex[2..] else hex[0..];
            var bytes: [size]u8 = undefined;
            for (0..size) |i| {
                const hi = std.fmt.charToDigit(hex_digits[i * 2], 16) catch
                    return FixedBytesError.InvalidHexDigit;
                const lo = std.fmt.charToDigit(hex_digits[i * 2 + 1], 16) catch
                    return FixedBytesError.InvalidHexDigit;
                bytes[i] = (hi << 4) | lo;
            }

            return Self{ .bytes = bytes };
        }

        /// Parse from a hex string (compile-time)
        ///
        /// This function can only be used at compile time. It's useful for defining
        /// constant byte arrays (e.g., well-known hashes, constants).
        ///
        /// Example:
        /// ```zig
        /// const B256 = FixedBytes(32);
        /// const zero_hash = B256.fromHexComptime("0x0000...0000"); // 64 hex digits
        /// ```
        pub fn fromHexComptime(comptime hex: []const u8) Self {
            @setEvalBranchQuota(5000);

            const expected_len = size * 2;
            const expected_len_with_prefix = expected_len + 2;

            if (hex.len != expected_len and hex.len != expected_len_with_prefix)
                @compileError("Hex string must be " ++ std.fmt.comptimePrint("{d}", .{expected_len}) ++ " hex digits (" ++ std.fmt.comptimePrint("{d}", .{size}) ++ " bytes), possibly with '0x' prefix");

            const hex_digits = if (hex.len == expected_len_with_prefix) hex[2..] else hex[0..];

            var bytes: [size]u8 = undefined;
            inline for (0..size) |i| {
                const hi = std.fmt.charToDigit(hex_digits[i * 2], 16) catch unreachable;
                const lo = std.fmt.charToDigit(hex_digits[i * 2 + 1], 16) catch unreachable;
                bytes[i] = (hi << 4) | lo;
            }

            return Self{ .bytes = bytes };
        }

        /// Create from a slice with length validation
        ///
        /// Returns an error if the slice length doesn't match the expected size.
        pub fn fromSlice(slice: []const u8) FixedBytesError!Self {
            if (slice.len != size)
                return FixedBytesError.InvalidSliceLength;

            var bytes: [size]u8 = undefined;
            @memcpy(&bytes, slice);
            return Self{ .bytes = bytes };
        }

        /// Create from a slice, left-padding with zeros if too short
        ///
        /// If the slice is longer than size, only the rightmost bytes are used.
        /// If the slice is shorter, it's left-padded with zeros.
        ///
        /// Example: For B256, [0x12, 0x34] becomes [0x00...00, 0x12, 0x34]
        pub fn leftPadFrom(value: []const u8) Self {
            var bytes = [_]u8{0} ** size;

            if (value.len >= size) {
                // Take rightmost bytes
                @memcpy(&bytes, value[value.len - size ..]);
            } else {
                // Left-pad with zeros
                @memcpy(bytes[size - value.len ..], value);
            }

            return Self{ .bytes = bytes };
        }

        /// Create from a slice, right-padding with zeros if too short
        ///
        /// If the slice is longer than size, only the leftmost bytes are used.
        /// If the slice is shorter, it's right-padded with zeros.
        ///
        /// Example: For B256, [0x12, 0x34] becomes [0x12, 0x34, 0x00...00]
        pub fn rightPadFrom(value: []const u8) Self {
            var bytes = [_]u8{0} ** size;

            if (value.len >= size) {
                // Take leftmost bytes
                @memcpy(&bytes, value[0..size]);
            } else {
                // Right-pad with zeros
                @memcpy(bytes[0..value.len], value);
            }

            return Self{ .bytes = bytes };
        }

        /// Zero-cost pointer cast from const array reference
        ///
        /// This is useful for performance-critical code where you want to
        /// reinterpret a byte array as a FixedBytes type without copying.
        pub fn fromRef(bytes: *const [size]u8) *const Self {
            return @ptrCast(bytes);
        }

        /// Zero-cost pointer cast from mutable array reference
        pub fn fromMut(bytes: *[size]u8) *Self {
            return @ptrCast(bytes);
        }

        /// Helper function for hex encoding
        ///
        /// offset: buffer offset (0 for no prefix, 2 for "0x" prefix)
        /// case: character case (.lower or .upper)
        fn toHexInternal(self: Self, buf: []u8, offset: usize, comptime case: std.fmt.Case) void {
            for (self.bytes, 0..) |byte, i| {
                buf[offset + i * 2] = std.fmt.digitToChar(byte >> 4, case);
                buf[offset + i * 2 + 1] = std.fmt.digitToChar(byte & 0x0F, case);
            }
        }

        /// Format as a hex string (lowercase, with "0x" prefix)
        ///
        /// The output buffer must be at least (size * 2 + 2) bytes.
        pub fn toHex(self: Self, buf: []u8) ![]const u8 {
            const required_len = size * 2 + 2;
            if (buf.len < required_len) return error.BufferTooSmall;

            buf[0] = '0';
            buf[1] = 'x';
            self.toHexInternal(buf, 2, .lower);

            return buf[0..required_len];
        }

        /// Format as a hex string (lowercase, without "0x" prefix)
        ///
        /// The output buffer must be at least (size * 2) bytes.
        pub fn toHexNoPrefix(self: Self, buf: []u8) ![]const u8 {
            const required_len = size * 2;
            if (buf.len < required_len) return error.BufferTooSmall;

            self.toHexInternal(buf, 0, .lower);

            return buf[0..required_len];
        }

        /// Format as a hex string (uppercase, with "0x" prefix)
        ///
        /// The output buffer must be at least (size * 2 + 2) bytes.
        pub fn toHexUpper(self: Self, buf: []u8) ![]const u8 {
            const required_len = size * 2 + 2;
            if (buf.len < required_len) return error.BufferTooSmall;

            buf[0] = '0';
            buf[1] = 'x';
            self.toHexInternal(buf, 2, .upper);

            return buf[0..required_len];
        }

        /// Get a const slice view of the bytes
        pub fn asSlice(self: *const Self) []const u8 {
            return &self.bytes;
        }

        /// Get a mutable slice view of the bytes
        pub fn asMutSlice(self: *Self) []u8 {
            return &self.bytes;
        }

        /// Check if two fixed bytes arrays are equal
        pub fn eql(self: Self, other: Self) bool {
            return std.mem.eql(u8, &self.bytes, &other.bytes);
        }

        /// Check if all bytes are zero
        pub fn isZero(self: Self) bool {
            for (self.bytes) |byte| {
                if (byte != 0) return false;
            }
            return true;
        }

        /// Format the fixed bytes for use with `std.fmt`
        ///
        /// Implements the standard Zig formatting protocol, allowing FixedBytes to be
        /// used with `std.fmt.format`, `std.fmt.bufPrint`, `std.fmt.allocPrint` etc.
        ///
        /// The bytes are formatted as a lowercase hex string with "0x" prefix.
        pub fn format(
            self: Self,
            writer: anytype,
        ) @TypeOf(writer.*).Error!void {
            var buf: [size * 2 + 2]u8 = undefined;
            // We know the buffer is large enough, so this can't fail with BufferTooSmall
            const hex = self.toHex(&buf) catch unreachable;
            try writer.writeAll(hex);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

test "FixedBytes - init" {
    const B32 = FixedBytes(32);
    const bytes = [_]u8{0x12} ++ [_]u8{0x00} ** 31;
    const fb = B32.init(bytes);
    try expect(fb.bytes[0] == 0x12);
    try expect(fb.bytes[31] == 0x00);
}

test "FixedBytes - zero" {
    const B32 = FixedBytes(32);
    const zero = B32.zero();
    try expect(zero.isZero());
}

test "FixedBytes - repeat" {
    const B32 = FixedBytes(32);
    const test_cases = [_]struct {
        byte: u8,
    }{
        .{ .byte = 0xFF },
        .{ .byte = 0x00 },
        .{ .byte = 0x42 },
    };

    for (test_cases) |tc| {
        const repeated = B32.repeat(tc.byte);
        for (repeated.bytes) |byte| {
            try expect(byte == tc.byte);
        }
    }
}

test "FixedBytes.fromHex - valid inputs" {
    const B4 = FixedBytes(4);
    const test_cases = [_]struct {
        input: []const u8,
        expected: [4]u8,
    }{
        // With 0x prefix, lowercase
        .{
            .input = "0x12345678",
            .expected = [_]u8{ 0x12, 0x34, 0x56, 0x78 },
        },
        // Without 0x prefix
        .{
            .input = "12345678",
            .expected = [_]u8{ 0x12, 0x34, 0x56, 0x78 },
        },
        // Uppercase hex
        .{
            .input = "0x12345678",
            .expected = [_]u8{ 0x12, 0x34, 0x56, 0x78 },
        },
        // All zeros
        .{
            .input = "0x00000000",
            .expected = [_]u8{ 0x00, 0x00, 0x00, 0x00 },
        },
        // All ones
        .{
            .input = "0xFFFFFFFF",
            .expected = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF },
        },
    };

    for (test_cases) |tc| {
        const fb = try B4.fromHex(tc.input);
        try expect(std.mem.eql(u8, &fb.bytes, &tc.expected));
    }
}

test "FixedBytes.fromHex - B256 valid" {
    const hex = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    const fb = try B256.fromHex(hex);
    try expect(fb.bytes[0] == 0x12);
    try expect(fb.bytes[31] == 0xef);
}

test "FixedBytes.fromHex - invalid inputs" {
    const B4 = FixedBytes(4);
    const test_cases = [_]struct {
        input: []const u8,
        expected_error: FixedBytesError,
    }{
        // Too short
        .{
            .input = "0x123456",
            .expected_error = FixedBytesError.InvalidHexStringLength,
        },
        // Too long
        .{
            .input = "0x123456789a",
            .expected_error = FixedBytesError.InvalidHexStringLength,
        },
        // Invalid character
        .{
            .input = "0x1234567z",
            .expected_error = FixedBytesError.InvalidHexDigit,
        },
        // Empty string
        .{
            .input = "",
            .expected_error = FixedBytesError.InvalidHexStringLength,
        },
        // Only 0x
        .{
            .input = "0x",
            .expected_error = FixedBytesError.InvalidHexStringLength,
        },
    };

    for (test_cases) |tc| {
        try expectError(tc.expected_error, B4.fromHex(tc.input));
    }
}

test "FixedBytes.fromHexComptime" {
    const B4 = FixedBytes(4);
    const test_cases = [_]struct {
        input: []const u8,
        expected: [4]u8,
    }{
        // With 0x prefix
        .{
            .input = "0x12345678",
            .expected = [_]u8{ 0x12, 0x34, 0x56, 0x78 },
        },
        // Without 0x prefix
        .{
            .input = "9abcdef0",
            .expected = [_]u8{ 0x9a, 0xbc, 0xde, 0xf0 },
        },
        // All zeros
        .{
            .input = "0x00000000",
            .expected = [_]u8{ 0x00, 0x00, 0x00, 0x00 },
        },
    };

    inline for (test_cases) |tc| {
        const fb = B4.fromHexComptime(tc.input);
        try expect(std.mem.eql(u8, &fb.bytes, &tc.expected));
    }
}

test "FixedBytes.fromSlice - valid" {
    const B4 = FixedBytes(4);
    const slice = [_]u8{ 0x12, 0x34, 0x56, 0x78 };
    const fb = try B4.fromSlice(&slice);
    try expect(std.mem.eql(u8, &fb.bytes, &slice));
}

test "FixedBytes.fromSlice - invalid length" {
    const B4 = FixedBytes(4);
    const slice_short = [_]u8{ 0x12, 0x34 };
    const slice_long = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9a };

    try expectError(FixedBytesError.InvalidSliceLength, B4.fromSlice(&slice_short));
    try expectError(FixedBytesError.InvalidSliceLength, B4.fromSlice(&slice_long));
}

test "FixedBytes.leftPadFrom" {
    const B8 = FixedBytes(8);
    const test_cases = [_]struct {
        input: []const u8,
        expected: [8]u8,
    }{
        // Shorter slice - should left-pad
        .{
            .input = &[_]u8{ 0x12, 0x34 },
            .expected = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x34 },
        },
        // Exact size - no padding
        .{
            .input = &[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 },
            .expected = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 },
        },
        // Longer slice - should take rightmost bytes
        .{
            .input = &[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a },
            .expected = [_]u8{ 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a },
        },
    };

    for (test_cases) |tc| {
        const result = B8.leftPadFrom(tc.input);
        try expect(std.mem.eql(u8, &result.bytes, &tc.expected));
    }
}

test "FixedBytes.rightPadFrom" {
    const B8 = FixedBytes(8);
    const test_cases = [_]struct {
        input: []const u8,
        expected: [8]u8,
    }{
        // Shorter slice - should right-pad
        .{
            .input = &[_]u8{ 0x12, 0x34 },
            .expected = [_]u8{ 0x12, 0x34, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        },
        // Exact size - no padding
        .{
            .input = &[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 },
            .expected = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 },
        },
        // Longer slice - should take leftmost bytes
        .{
            .input = &[_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a },
            .expected = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 },
        },
    };

    for (test_cases) |tc| {
        const result = B8.rightPadFrom(tc.input);
        try expect(std.mem.eql(u8, &result.bytes, &tc.expected));
    }
}

test "FixedBytes.fromRef and fromMut" {
    const B4 = FixedBytes(4);
    var bytes = [_]u8{ 0x12, 0x34, 0x56, 0x78 };

    // Test fromRef (const)
    const fb_ref = B4.fromRef(&bytes);
    try expect(std.mem.eql(u8, &fb_ref.bytes, &bytes));

    // Test fromMut
    const fb_mut = B4.fromMut(&bytes);
    try expect(std.mem.eql(u8, &fb_mut.bytes, &bytes));

    // Verify it's actually the same memory
    fb_mut.bytes[0] = 0xFF;
    try expect(bytes[0] == 0xFF);
}

test "FixedBytes.toHex" {
    const B4 = FixedBytes(4);
    const test_cases = [_]struct {
        input: [4]u8,
        expected: []const u8,
    }{
        // Basic formatting
        .{
            .input = [_]u8{ 0x12, 0x34, 0x56, 0x78 },
            .expected = "0x12345678",
        },
        // All zeros
        .{
            .input = [_]u8{ 0x00, 0x00, 0x00, 0x00 },
            .expected = "0x00000000",
        },
        // All ones (should be lowercase)
        .{
            .input = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF },
            .expected = "0xffffffff",
        },
        // Mixed
        .{
            .input = [_]u8{ 0xab, 0xcd, 0xef, 0x01 },
            .expected = "0xabcdef01",
        },
    };

    for (test_cases) |tc| {
        const fb = B4.init(tc.input);
        var buf: [20]u8 = undefined;
        const hex = try fb.toHex(&buf);
        try expectEqualStrings(tc.expected, hex);
    }
}

test "FixedBytes.toHexNoPrefix" {
    const B4 = FixedBytes(4);
    const fb = B4.init([_]u8{ 0x12, 0x34, 0x56, 0x78 });
    var buf: [20]u8 = undefined;
    const hex = try fb.toHexNoPrefix(&buf);
    try expectEqualStrings("12345678", hex);
}

test "FixedBytes.toHexUpper" {
    const B4 = FixedBytes(4);
    const fb = B4.init([_]u8{ 0xab, 0xcd, 0xef, 0x12 });
    var buf: [20]u8 = undefined;
    const hex = try fb.toHexUpper(&buf);
    try expectEqualStrings("0xABCDEF12", hex);
}

test "FixedBytes.toHex - buffer too small" {
    const B4 = FixedBytes(4);
    const fb = B4.init([_]u8{ 0x12, 0x34, 0x56, 0x78 });
    var buf: [5]u8 = undefined; // Too small, needs at least 10 (2 + 4*2)
    try expectError(error.BufferTooSmall, fb.toHex(&buf));
}

test "FixedBytes.asSlice and asMutSlice" {
    const B4 = FixedBytes(4);
    var fb = B4.init([_]u8{ 0x12, 0x34, 0x56, 0x78 });

    // Test asSlice
    const slice = fb.asSlice();
    try expect(slice.len == 4);
    try expect(slice[0] == 0x12);

    // Test asMutSlice
    const mut_slice = fb.asMutSlice();
    mut_slice[0] = 0xFF;
    try expect(fb.bytes[0] == 0xFF);
}

test "FixedBytes.eql" {
    const B4 = FixedBytes(4);
    const test_cases = [_]struct {
        a: [4]u8,
        b: [4]u8,
        is_equal: bool,
    }{
        // Same bytes
        .{
            .a = [_]u8{ 0x12, 0x34, 0x56, 0x78 },
            .b = [_]u8{ 0x12, 0x34, 0x56, 0x78 },
            .is_equal = true,
        },
        // Different bytes
        .{
            .a = [_]u8{ 0x12, 0x34, 0x56, 0x78 },
            .b = [_]u8{ 0x12, 0x34, 0x56, 0x79 },
            .is_equal = false,
        },
        // All zeros
        .{
            .a = [_]u8{ 0x00, 0x00, 0x00, 0x00 },
            .b = [_]u8{ 0x00, 0x00, 0x00, 0x00 },
            .is_equal = true,
        },
    };

    for (test_cases) |tc| {
        const a = B4.init(tc.a);
        const b = B4.init(tc.b);
        try expect(a.eql(b) == tc.is_equal);
    }
}

test "FixedBytes.isZero" {
    const B4 = FixedBytes(4);
    const test_cases = [_]struct {
        input: [4]u8,
        is_zero: bool,
    }{
        // All zeros
        .{
            .input = [_]u8{ 0x00, 0x00, 0x00, 0x00 },
            .is_zero = true,
        },
        // Not zero - last byte
        .{
            .input = [_]u8{ 0x00, 0x00, 0x00, 0x01 },
            .is_zero = false,
        },
        // Not zero - first byte
        .{
            .input = [_]u8{ 0x01, 0x00, 0x00, 0x00 },
            .is_zero = false,
        },
        // Not zero - middle byte
        .{
            .input = [_]u8{ 0x00, 0x01, 0x00, 0x00 },
            .is_zero = false,
        },
    };

    for (test_cases) |tc| {
        const fb = B4.init(tc.input);
        try expect(fb.isZero() == tc.is_zero);
    }

    // Zero from constructor
    const zero_const = B4.zero();
    try expect(zero_const.isZero());
}

test "FixedBytes round-trip: hex -> FixedBytes -> hex" {
    const B4 = FixedBytes(4);
    const test_cases = [_][]const u8{
        "0x12345678",
        "0x00000000",
        "0xabcdef01",
        "0xffffffff",
    };

    for (test_cases) |original| {
        const fb = try B4.fromHex(original);
        var buf: [20]u8 = undefined;
        const result = try fb.toHex(&buf);
        try expectEqualStrings(original, result);
    }
}

test "FixedBytes.format" {
    const B4 = FixedBytes(4);
    const test_cases = [_]struct {
        input: [4]u8,
        expected: []const u8,
    }{
        .{
            .input = [_]u8{ 0x12, 0x34, 0x56, 0x78 },
            .expected = "0x12345678",
        },
        .{
            .input = [_]u8{ 0xab, 0xcd, 0xef, 0x01 },
            .expected = "0xabcdef01",
        },
        .{
            .input = [_]u8{ 0x00, 0x00, 0x00, 0x00 },
            .expected = "0x00000000",
        },
    };

    for (test_cases) |tc| {
        const fb = B4.init(tc.input);

        // Test with bufPrint
        var buf: [100]u8 = undefined;
        const result = try std.fmt.bufPrint(&buf, "{f}", .{fb});
        try expectEqualStrings(tc.expected, result);

        // Test with bufPrint in a longer format string
        const result2 = try std.fmt.bufPrint(&buf, "Value: {f}", .{fb});
        var buf2: [100]u8 = undefined;
        const expected_with_prefix = try std.fmt.bufPrint(&buf2, "Value: {s}", .{tc.expected});
        try expectEqualStrings(expected_with_prefix, result2);

        // Test with allocPrint
        const allocator = std.testing.allocator;
        const result3 = try std.fmt.allocPrint(allocator, "{f}", .{fb});
        defer allocator.free(result3);
        try expectEqualStrings(tc.expected, result3);
    }
}

test "B256 - basic usage" {
    const test_cases = [_]struct {
        hex: []const u8,
        is_zero: bool,
        expected_first: u8,
        expected_last: u8,
    }{
        // Zero hash
        .{
            .hex = "0x0000000000000000000000000000000000000000000000000000000000000000",
            .is_zero = true,
            .expected_first = 0x00,
            .expected_last = 0x00,
        },
        // One
        .{
            .hex = "0x0000000000000000000000000000000000000000000000000000000000000001",
            .is_zero = false,
            .expected_first = 0x00,
            .expected_last = 0x01,
        },
        // Non-zero hash
        .{
            .hex = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
            .is_zero = false,
            .expected_first = 0x12,
            .expected_last = 0xef,
        },
    };

    for (test_cases) |tc| {
        const hash = try B256.fromHex(tc.hex);
        try expect(hash.isZero() == tc.is_zero);
        try expect(hash.bytes[0] == tc.expected_first);
        try expect(hash.bytes[31] == tc.expected_last);

        // Test formatting
        var buf: [100]u8 = undefined;
        const formatted = try std.fmt.bufPrint(&buf, "{f}", .{hash});
        try expectEqualStrings(tc.hex, formatted);
    }
}

test "B256 - compile-time constant" {
    const empty_hash = B256.fromHexComptime("0x0000000000000000000000000000000000000000000000000000000000000000");
    try expect(empty_hash.isZero());

    const some_hash = B256.fromHexComptime("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef");
    try expect(!some_hash.isZero());
    try expect(some_hash.bytes[0] == 0x12);
    try expect(some_hash.bytes[31] == 0xef);
}

test "B160 - basic usage" {
    const test_cases = [_]struct {
        hex: []const u8,
        is_zero: bool,
        expected_first: u8,
        expected_last: u8,
    }{
        // Zero address
        .{
            .hex = "0x0000000000000000000000000000000000000000",
            .is_zero = true,
            .expected_first = 0x00,
            .expected_last = 0x00,
        },
        // Non-zero address
        .{
            .hex = "0x1234567890123456789012345678901234567890",
            .is_zero = false,
            .expected_first = 0x12,
            .expected_last = 0x90,
        },
    };

    for (test_cases) |tc| {
        const value = try B160.fromHex(tc.hex);
        try expect(value.isZero() == tc.is_zero);
        try expect(value.bytes[0] == tc.expected_first);
        try expect(value.bytes[19] == tc.expected_last);
    }
}

test "FixedBytes - different sizes" {
    const test_cases = [_]struct {
        size: usize,
    }{
        .{ .size = 1 },
        .{ .size = 8 },
        .{ .size = 16 },
        .{ .size = 32 },
        .{ .size = 64 },
    };

    inline for (test_cases) |tc| {
        const T = FixedBytes(tc.size);
        const zero = T.zero();
        try expect(zero.bytes.len == tc.size);
        try expect(zero.isZero());
    }
}
