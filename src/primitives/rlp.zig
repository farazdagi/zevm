//! Minimal RLP (Recursive Length Prefix) encoding for CREATE address calculation.
//!
//! This module provides only the functionality needed for encoding [address, nonce]
//! tuples required by the CREATE opcode.
//!
//! RLP Specification: https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/

const std = @import("std");
const Allocator = std.mem.Allocator;
const Address = @import("address.zig").Address;

/// Encode [address, nonce] for CREATE address derivation.
/// Returns allocated buffer that caller must free.
/// Max size: ~30 bytes for address+nonce encoding.
pub fn encodeAddressNonce(allocator: Allocator, address: Address, nonce: u64) ![]u8 {
    // RLP encoding of [address, nonce]:
    // - List prefix: 0xc0 + total_length (if length < 56)
    //   or 0xf7 + length_of_length + length bytes (if length >= 56)
    // - Address: 0x94 + 20 bytes (address is always 20 bytes, so 0x80 + 20 = 0x94)
    // - Nonce: encoded as shortest big-endian representation
    //   - 0x80: nonce = 0 (empty string)
    //   - 0x01-0x7f: nonce = 1-127 (single byte, value itself)
    //   - 0x80 + len + bytes: nonce >= 128

    // Calculate nonce encoding length first.
    const nonce_encoding_len = nonceEncodingLength(nonce);

    // Address is always 21 bytes (0x94 prefix + 20 bytes).
    const address_encoding_len: usize = 21;

    // Total payload length.
    const payload_len = address_encoding_len + nonce_encoding_len;

    // List prefix length (always < 56 for our use case, so 1 byte).
    const list_prefix_len: usize = 1;

    // Total buffer size.
    const total_len = list_prefix_len + payload_len;

    // Allocate buffer.
    var buffer = try allocator.alloc(u8, total_len);
    errdefer allocator.free(buffer);

    var offset: usize = 0;

    // Write list prefix (0xc0 + payload_len).
    buffer[offset] = 0xc0 + @as(u8, @intCast(payload_len));
    offset += 1;

    // Write address (0x94 + 20 bytes).
    buffer[offset] = 0x94;
    offset += 1;
    @memcpy(buffer[offset .. offset + 20], &address.inner.bytes);
    offset += 20;

    // Write nonce.
    encodeNonce(buffer[offset..], nonce);

    return buffer;
}

/// Calculate the RLP encoding length for a nonce value.
fn nonceEncodingLength(nonce: u64) usize {
    // 0x80 (empty string) or single byte
    if (nonce < 0x80) {
        return 1;
    }
    // Multi-byte encoding: 0x80 + len + bytes.
    return 1 + nonceByteLength(nonce); // Prefix + bytes
}

/// Calculate the number of bytes needed to represent nonce in big-endian.
fn nonceByteLength(nonce: u64) usize {
    if (nonce == 0) return 0;
    const bits: usize = 64 - @clz(nonce);
    return (bits + 7) / 8;
}

/// Encode nonce into buffer (buffer must be large enough).
fn encodeNonce(buffer: []u8, nonce: u64) void {
    if (nonce == 0) {
        buffer[0] = 0x80; // Empty string
    } else if (nonce < 0x80) {
        buffer[0] = @intCast(nonce); // Single byte
    } else {
        // Multi-byte encoding.
        const byte_len = nonceByteLength(nonce);
        buffer[0] = 0x80 + @as(u8, @intCast(byte_len));

        // Write nonce as big-endian bytes.
        var n = nonce;
        var i: usize = byte_len;
        while (i > 0) {
            i -= 1;
            buffer[1 + i] = @intCast(n & 0xFF);
            n >>= 8;
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

const expectEqualSlices = std.testing.expectEqualSlices;
const testing = std.testing;

test "RLP: encodeAddressNonce" {
    const allocator = testing.allocator;
    const address = Address.zero();

    const TestCase = struct {
        nonce: u64,
        expected: []const u8,
    };

    const test_cases = [_]TestCase{
        // nonce 0: empty string encoding (0x80).
        // Geth: rlp.EncodeToBytes([]interface{}{common.HexToAddress("0x00...00"), uint64(0)})
        .{ .nonce = 0, .expected = &([_]u8{0xd6} ++ [_]u8{0x94} ++ ([_]u8{0} ** 20) ++ [_]u8{0x80}) },

        // nonce 1: single byte encoding.
        .{ .nonce = 1, .expected = &([_]u8{0xd6} ++ [_]u8{0x94} ++ ([_]u8{0} ** 20) ++ [_]u8{0x01}) },

        // nonce 5: geth vector - single byte encoding.
        .{ .nonce = 5, .expected = &([_]u8{0xd6} ++ [_]u8{0x94} ++ ([_]u8{0} ** 20) ++ [_]u8{0x05}) },

        // nonce 127: boundary case - last value that fits in single byte.
        .{ .nonce = 127, .expected = &([_]u8{0xd6} ++ [_]u8{0x94} ++ ([_]u8{0} ** 20) ++ [_]u8{0x7f}) },

        // nonce 128: boundary case - first value requiring multi-byte encoding.
        // Encodes as 0x81 (string of length 1) + 0x80 (value 128).
        .{ .nonce = 128, .expected = &([_]u8{0xd7} ++ [_]u8{0x94} ++ ([_]u8{0} ** 20) ++ [_]u8{ 0x81, 0x80 }) },

        // nonce 256: 2-byte encoding (0x82 + 0x01 0x00).
        .{ .nonce = 256, .expected = &([_]u8{0xd8} ++ [_]u8{0x94} ++ ([_]u8{0} ** 20) ++ [_]u8{ 0x82, 0x01, 0x00 }) },

        // nonce 1000: geth vector - 2-byte encoding.
        // 1000 = 0x03e8, encodes as 0x82 (string of length 2) + 0x03 0xe8.
        .{ .nonce = 1000, .expected = &([_]u8{0xd8} ++ [_]u8{0x94} ++ ([_]u8{0} ** 20) ++ [_]u8{ 0x82, 0x03, 0xe8 }) },
    };

    for (test_cases) |tc| {
        const encoded = try encodeAddressNonce(allocator, address, tc.nonce);
        defer allocator.free(encoded);
        try expectEqualSlices(u8, tc.expected, encoded);
    }
}
