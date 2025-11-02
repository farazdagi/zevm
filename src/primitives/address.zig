const std = @import("std");
const bytes = @import("bytes.zig");
const B160 = bytes.B160;
const FixedBytesError = bytes.FixedBytesError;

/// Ethereum address errors
pub const AddressError = error{
    InvalidHexStringLength,
    InvalidHexDigit,
    InvalidChecksumFormat,
};

/// Ethereum address type
///
/// Represents a 20-byte Ethereum address. Ethereum addresses are derived from
/// the rightmost 160 bits (20 bytes) of the Keccak-256 hash of the public key.
///
/// This implementation supports:
/// - Basic hex parsing and formatting
/// - EIP-55: Mixed-case checksum address encoding
/// - EIP-1191: Chain-specific checksummed addresses (extends EIP-55)
///
/// References:
/// - EIP-55: https://eips.ethereum.org/EIPS/eip-55
/// - EIP-1191: https://eips.ethereum.org/EIPS/eip-1191
pub const Address = struct {
    inner: B160,

    /// Initialize an address from a 20-byte array
    pub fn init(b: [20]u8) Address {
        return Address{ .inner = B160.init(b) };
    }

    /// Create a zero-filled address
    pub fn zero() Address {
        return Address{ .inner = B160.zero() };
    }

    /// Check if the address is all zeros
    pub fn isZero(self: Address) bool {
        return self.inner.isZero();
    }

    /// Parse an address from a hex string (run-time)
    ///
    /// Accepts hex strings with or without "0x" prefix.
    /// The hex string must represent exactly 20 bytes (40 hex digits).
    ///
    /// This function does NOT validate EIP-55 checksums.
    /// Use `fromChecksummedHex` if you want to validate the checksum.
    ///
    /// Examples:
    /// - "0xd8da6bf26964af9d7eed9e03e53415d37aa96045" (with prefix)
    /// - "d8da6bf26964af9d7eed9e03e53415d37aa96045" (without prefix)
    /// - "0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045" (uppercase)
    pub fn fromHex(hex: []const u8) AddressError!Address {
        const b160 = B160.fromHex(hex) catch |err| switch (err) {
            FixedBytesError.InvalidHexStringLength => return AddressError.InvalidHexStringLength,
            FixedBytesError.InvalidHexDigit => return AddressError.InvalidHexDigit,
            else => unreachable,
        };
        return Address{ .inner = b160 };
    }

    /// Parse an address from a hex string (compile-time)
    ///
    /// This function can only be used at compile time. It's useful for defining
    /// constant addresses (e.g., precompile addresses, system contracts).
    ///
    /// Example:
    /// ```zig
    /// const zero_address = address("0x0000000000000000000000000000000000000000");
    /// ```
    pub fn fromHexComptime(comptime hex: []const u8) Address {
        return Address{ .inner = B160.fromHexComptime(hex) };
    }

    /// Parse an address from a checksummed hex string and validate the checksum
    ///
    /// Validates EIP-55 checksums (or EIP-1191 if `chain_id` is provided).
    ///
    /// For backward compatibility with pre-EIP-55 addresses, all-lowercase and all-uppercase
    /// addresses are accepted without checksum validation (checksum encoding requires mixed case).
    ///
    /// Parameters:
    /// - hex: The checksummed hex string (with or without "0x" prefix)
    /// - chain_id: Optional chain ID for EIP-1191 validation. If null, uses EIP-55.
    pub fn fromChecksummedHex(hex: []const u8, chain_id: ?u64) AddressError!Address {
        if (hex.len != 40 and hex.len != 42)
            return AddressError.InvalidHexStringLength;

        const hex_digits = if (hex.len == 42) hex[2..] else hex[0..];

        // Check if all lowercase or all uppercase (no checksum to validate)
        var has_lowercase = false;
        var has_uppercase = false;
        for (hex_digits) |c| {
            if (c >= 'a' and c <= 'f') has_lowercase = true;
            if (c >= 'A' and c <= 'F') has_uppercase = true;
            if (has_lowercase and has_uppercase) break;
        }

        // All lowercase or all uppercase = no checksum, just parse
        if (!has_lowercase or !has_uppercase) {
            return fromHex(hex);
        }

        // Mixed case, parse and validate
        const addr = try fromHex(hex);
        if (!addr.validateChecksum(hex_digits, chain_id)) {
            return AddressError.InvalidChecksumFormat;
        }

        return addr;
    }

    /// Format address as a hex string (lowercase, with "0x" prefix)
    pub fn toHex(self: Address, buf: []u8) ![]const u8 {
        return self.inner.toHex(buf);
    }

    /// Format address as a checksummed hex string per EIP-55 or EIP-1191
    ///
    /// EIP-55 specifies mixed-case checksumming: each alphabetic hex character
    /// is capitalized if the corresponding nibble in the hash is >= 8.
    /// The hash is computed over the lowercase hex address (without 0x prefix).
    ///
    /// EIP-1191 extends this by including the chain ID in the hash calculation,
    /// making checksums chain-specific and preventing address reuse across chains.
    /// When a chain_id is provided, the hash is computed over "chainId + 0x + address".
    ///
    /// **Note**: The official ERC-1191 specification states that the chain-specific
    /// checksum should only be used for networks that have "opted in" (specifically
    /// RSK Mainnet=30 and RSK Testnet=31). However, in this implementation if `chain_id`
    /// is provided, EIP-1191 is used for ANY chain ID, otherwise EIP-55 is used.
    ///
    /// This provides the maximum flexibility: end-users can choose whether to use
    /// chain-specific encoding or not.
    ///
    /// Parameters:
    /// - buf: Output buffer for the formatted address
    /// - chain_id: Optional chain ID. If provided, uses EIP-1191; if null, uses EIP-55.
    ///
    /// Returns a slice of the buffer containing the formatted checksummed address.
    ///
    /// References:
    /// - EIP-55: https://eips.ethereum.org/EIPS/eip-55
    /// - EIP-1191/ERC-1191: https://eips.ethereum.org/EIPS/eip-1191
    pub fn toChecksummedHex(self: Address, buf: []u8, chain_id: ?u64) ![]const u8 {
        // The output buffer must be at least 42 bytes (2 for "0x" + 40 for hex digits).
        if (buf.len < 42) return error.BufferTooSmall;

        buf[0] = '0';
        buf[1] = 'x';

        // First, convert address to lowercase hex (without 0x prefix)
        var addr_hex: [40]u8 = undefined;
        for (self.inner.bytes, 0..) |byte, i| {
            addr_hex[i * 2] = std.fmt.digitToChar(byte >> 4, .lower);
            addr_hex[i * 2 + 1] = std.fmt.digitToChar(byte & 0x0F, .lower);
        }

        // Compute the hash for checksumming
        var hash_input: [80]u8 = undefined; // Max size needed for EIP-1191
        var hash_input_len: usize = 0;

        if (chain_id) |id| {
            // EIP-1191: Hash "chainId + 0x + address"
            // Format chain ID as decimal string
            var chain_buf: [20]u8 = undefined;
            const chain_str = std.fmt.bufPrint(&chain_buf, "{d}", .{id}) catch unreachable;

            @memcpy(hash_input[0..chain_str.len], chain_str);
            hash_input[chain_str.len] = '0';
            hash_input[chain_str.len + 1] = 'x';
            @memcpy(hash_input[chain_str.len + 2 .. chain_str.len + 2 + 40], &addr_hex);
            hash_input_len = chain_str.len + 2 + 40;
        } else {
            // EIP-55: Hash just the lowercase address (no 0x prefix)
            @memcpy(hash_input[0..40], &addr_hex);
            hash_input_len = 40;
        }

        // Compute Keccak-256 hash
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha3.Keccak256.hash(hash_input[0..hash_input_len], &hash, .{});

        // Capitalize characters based on hash bits
        for (addr_hex, 0..) |c, i| {
            // For a given byte in the hash, get the corresponding nibble:
            // if i is even, get high nibble (by shifting it to right, and masking/zeroing left side);
            // if odd, get low nibble (by directly masking left side).
            const nibble = (hash[i / 2] >> @intCast(4 * (1 - i % 2))) & 0xf;
            // To uppercase `a..=f` you need to subtract 32 from the ASCII code,
            // or set bit 5 to 0 (XOR char with 0b0010_0000 if uppercase is needed).
            buf[2 + i] = c ^ (@as(u8, 0b0010_0000) * @intFromBool(c >= 'a' and c <= 'f' and nibble >= 8));
        }

        return buf[0..42];
    }

    /// Validate the checksum of a hex string against this address
    fn validateChecksum(self: Address, hex_digits: []const u8, chain_id: ?u64) bool {
        // The hex string should be 40 characters (without "0x" prefix).
        if (hex_digits.len != 40) return false;

        // Generate the expected checksummed version
        var expected_buf: [42]u8 = undefined;
        // Expected will be "0x" + 40 chars
        const expected = self.toChecksummedHex(&expected_buf, chain_id) catch return false;

        for (0..40) |i| {
            if (hex_digits[i] != expected[2 + i]) return false;
        }

        return true;
    }

    /// Check if two addresses are equal
    pub fn eql(self: Address, other: Address) bool {
        return self.inner.eql(other.inner);
    }

    /// Format the address for use with `std.fmt`
    ///
    /// Implements the standard Zig formatting protocol, allowing Address to be
    /// used with `std.fmt.format`, `std.fmt.bufPrint`, `std.fmt.allocPrint` etc.
    ///
    /// The address is formatted as a checksummed hex string (EIP-55).
    ///
    /// Example:
    /// ```zig
    /// const addr = try Address.fromHex("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");
    ///
    /// // With bufPrint
    /// var buf: [100]u8 = undefined;
    /// const s = try std.fmt.bufPrint(&buf, "Address: {f}", .{addr});
    ///
    /// // With allocPrint
    /// const s2 = try std.fmt.allocPrint(allocator, "{f}", .{addr});
    /// defer allocator.free(s2);
    /// ```
    pub fn format(
        self: Address,
        writer: anytype,
    ) @TypeOf(writer.*).Error!void {
        var buf: [42]u8 = undefined;
        // We know the buffer is large enough, so this can't fail with BufferTooSmall
        const hex = self.toChecksummedHex(&buf, null) catch unreachable;
        try writer.writeAll(hex);
    }
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

test "Address.fromHex - valid addresses" {
    const test_cases = [_]struct {
        input: []const u8,
        expected_first: u8,
        expected_last: u8,
    }{
        // With 0x prefix, lowercase
        .{
            .input = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
            .expected_first = 0xd8,
            .expected_last = 0x45,
        },
        // Without 0x prefix
        .{
            .input = "d8da6bf26964af9d7eed9e03e53415d37aa96045",
            .expected_first = 0xd8,
            .expected_last = 0x45,
        },
        // Uppercase hex
        .{
            .input = "0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045",
            .expected_first = 0xd8,
            .expected_last = 0x45,
        },
        // Mixed case
        .{
            .input = "0xD8da6BF26964af9d7eed9e03e53415d37aa96045",
            .expected_first = 0xd8,
            .expected_last = 0x45,
        },
        // All zeros
        .{
            .input = "0x0000000000000000000000000000000000000000",
            .expected_first = 0x00,
            .expected_last = 0x00,
        },
        // All ones
        .{
            .input = "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
            .expected_first = 0xFF,
            .expected_last = 0xFF,
        },
    };

    for (test_cases) |tc| {
        const addr = try Address.fromHex(tc.input);
        try expect(addr.inner.bytes[0] == tc.expected_first);
        try expect(addr.inner.bytes[19] == tc.expected_last);
    }
}

test "Address.fromHex - invalid inputs" {
    const test_cases = [_]struct {
        input: []const u8,
        expected_error: AddressError,
    }{
        // Too short
        .{
            .input = "0xd8da6bf26964af9d7eed9e03e53415d37aa9604",
            .expected_error = AddressError.InvalidHexStringLength,
        },
        // Too long
        .{
            .input = "0xd8da6bf26964af9d7eed9e03e53415d37aa9604500",
            .expected_error = AddressError.InvalidHexStringLength,
        },
        // Invalid character
        .{
            .input = "0xd8da6bf26964af9d7eed9e03e53415d37aa9604z",
            .expected_error = AddressError.InvalidHexDigit,
        },
        // Empty string
        .{
            .input = "",
            .expected_error = AddressError.InvalidHexStringLength,
        },
        // Only 0x
        .{
            .input = "0x",
            .expected_error = AddressError.InvalidHexStringLength,
        },
    };

    for (test_cases) |tc| {
        try expectError(tc.expected_error, Address.fromHex(tc.input));
    }
}

test "Address.toHex" {
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        // Basic formatting
        .{
            .input = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
            .expected = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
        },
        // Zero address
        .{
            .input = "0x0000000000000000000000000000000000000000",
            .expected = "0x0000000000000000000000000000000000000000",
        },
        // All ones (should be lowercase)
        .{
            .input = "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
            .expected = "0xffffffffffffffffffffffffffffffffffffffff",
        },
        // Mixed case input (should output lowercase)
        .{
            .input = "0xD8da6BF26964af9d7eed9e03e53415d37aa96045",
            .expected = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
        },
    };

    for (test_cases) |tc| {
        const addr = try Address.fromHex(tc.input);
        var buf: [42]u8 = undefined;
        const hex = try addr.toHex(&buf);
        try expectEqualStrings(tc.expected, hex);
    }
}

test "Address.eql" {
    const test_cases = [_]struct {
        addr1: []const u8,
        addr2: []const u8,
        is_equal: bool,
    }{
        // Same address, different case
        .{
            .addr1 = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
            .addr2 = "0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045",
            .is_equal = true,
        },
        // Different addresses
        .{
            .addr1 = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
            .addr2 = "0xb8da6bf26964af9d7eed9e03e53415d37aa96045",
            .is_equal = false,
        },
        // Same zero address
        .{
            .addr1 = "0x0000000000000000000000000000000000000000",
            .addr2 = "0x0000000000000000000000000000000000000000",
            .is_equal = true,
        },
    };

    for (test_cases) |tc| {
        const a1 = try Address.fromHex(tc.addr1);
        const a2 = try Address.fromHex(tc.addr2);
        try expect(a1.eql(a2) == tc.is_equal);
    }
}

test "Address.toChecksummedHex - EIP-55 specs test vectors" {
    // Test vectors from EIP-55 specification
    // Source: https://eips.ethereum.org/EIPS/eip-55
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        // All caps - these addresses happen to checksum to all uppercase
        .{
            .input = "0x52908400098527886E0F7030069857D2E4169EE7",
            .expected = "0x52908400098527886E0F7030069857D2E4169EE7",
        },
        .{
            .input = "0x8617E340B3D01FA5F11F306F4090FD50E238070D",
            .expected = "0x8617E340B3D01FA5F11F306F4090FD50E238070D",
        },
        // All lowercase - these addresses happen to checksum to all lowercase
        .{
            .input = "0xde709f2102306220921060314715629080e2fb77",
            .expected = "0xde709f2102306220921060314715629080e2fb77",
        },
        .{
            .input = "0x27b1fdb04752bbc536007a920d24acb045561c26",
            .expected = "0x27b1fdb04752bbc536007a920d24acb045561c26",
        },
        // Mixed case - some chars are uppercased, some are not
        .{
            .input = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
            .expected = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
        },
        .{
            .input = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
            .expected = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
        },
        .{
            .input = "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
            .expected = "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
        },
        .{
            .input = "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
            .expected = "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
        },
    };

    for (test_cases) |tc| {
        const addr = try Address.fromHex(tc.input);
        var buf: [42]u8 = undefined;
        const checksummed = try addr.toChecksummedHex(&buf, null);
        try expectEqualStrings(tc.expected, checksummed);
    }
}

test "Address.fromChecksummedHex - EIP-55 validation" {
    const test_cases = [_]struct {
        input: []const u8,
        should_succeed: bool,
    }{
        // Valid checksummed addresses
        .{ .input = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", .should_succeed = true },
        .{ .input = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359", .should_succeed = true },
        .{ .input = "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB", .should_succeed = true },
        // All lowercase (no checksum - should succeed)
        .{ .input = "0xde709f2102306220921060314715629080e2fb77", .should_succeed = true },
        // All uppercase (no checksum - should succeed)
        .{ .input = "0x52908400098527886E0F7030069857D2E4169EE7", .should_succeed = true },
        // Invalid checksum (last char should be 'd' not 'D')
        .{ .input = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD", .should_succeed = false },
    };

    for (test_cases) |tc| {
        if (tc.should_succeed) {
            _ = try Address.fromChecksummedHex(tc.input, null);
        } else {
            try expectError(AddressError.InvalidChecksumFormat, Address.fromChecksummedHex(tc.input, null));
        }
    }
}

test "Address.toChecksummedHex - EIP-1191 opted-in chains (30, 31)" {
    // Test vectors from EIP-1191 specification for opted-in chains
    // Source: https://eips.ethereum.org/EIPS/eip-1191
    //
    // NOTE: EIP-1191 was officially adopted only by RSK Mainnet (30) and RSK Testnet (31).

    const test_cases = [_]struct {
        input: []const u8,
        chain_id: u64,
        expected: []const u8,
    }{
        // Address 1: 0x27b1fdb04752bbc536007a920d24acb045561c26
        .{
            .input = "0x27b1fdb04752bbc536007a920d24acb045561c26",
            .chain_id = 30,
            .expected = "0x27b1FdB04752BBc536007A920D24ACB045561c26",
        },
        .{
            .input = "0x27b1fdb04752bbc536007a920d24acb045561c26",
            .chain_id = 31,
            .expected = "0x27B1FdB04752BbC536007a920D24acB045561C26",
        },
        // Address 2: 0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed
        .{
            .input = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
            .chain_id = 30,
            .expected = "0x5aaEB6053f3e94c9b9a09f33669435E7ef1bEAeD",
        },
        .{
            .input = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
            .chain_id = 31,
            .expected = "0x5aAeb6053F3e94c9b9A09F33669435E7EF1BEaEd",
        },
        // Address 3: 0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb
        .{
            .input = "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
            .chain_id = 30,
            .expected = "0xD1220A0Cf47c7B9BE7a2e6ba89F429762E7B9adB",
        },
        .{
            .input = "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
            .chain_id = 31,
            .expected = "0xd1220a0CF47c7B9Be7A2E6Ba89f429762E7b9adB",
        },
        // Address 4: 0x3599689E6292b81B2d85451025146515070129Bb
        .{
            .input = "0x3599689E6292b81B2d85451025146515070129Bb",
            .chain_id = 30,
            .expected = "0x3599689E6292B81B2D85451025146515070129Bb",
        },
        .{
            .input = "0x3599689E6292b81B2d85451025146515070129Bb",
            .chain_id = 31,
            .expected = "0x3599689e6292b81b2D85451025146515070129Bb",
        },
    };

    for (test_cases) |tc| {
        const addr = try Address.fromHex(tc.input);
        var buf: [42]u8 = undefined;
        const checksummed = try addr.toChecksummedHex(&buf, tc.chain_id);
        try expectEqualStrings(tc.expected, checksummed);
    }
}

test "Address.toChecksummedHex - EIP-1191 for non-opted-in chains" {
    // Test EIP-1191 behavior for non-opted-in chains
    // For chains that didn't officially adopt EIP-1191, our implementation still
    // applies EIP-1191 when chain_id is provided (for flexibility with L2s).

    const test_cases = [_]struct {
        input: []const u8,
        chain_id: ?u64,
        expected: []const u8,
    }{
        // Chain ID 1 (Ethereum Mainnet - not opted in to EIP-1191)
        .{
            .input = "0x27b1fdb04752bbc536007a920d24acb045561c26",
            .chain_id = 1,
            .expected = "0x27b1FdB04752bBc536007a920D24ACB045561c26",
        },
        // Without chain_id (null), use EIP-55
        .{
            .input = "0x27b1fdb04752bbc536007a920d24acb045561c26",
            .chain_id = null,
            .expected = "0x27b1fdb04752bbc536007a920d24acb045561c26",
        },
        // Chain ID 10 (Optimism - not opted in)
        .{
            .input = "0x27b1fdb04752bbc536007a920d24acb045561c26",
            .chain_id = 10,
            .expected = "0x27B1fDB04752BBC536007a920D24acB045561C26",
        },
    };

    for (test_cases) |tc| {
        const addr = try Address.fromHex(tc.input);
        var buf: [42]u8 = undefined;
        const checksummed = try addr.toChecksummedHex(&buf, tc.chain_id);
        try expectEqualStrings(tc.expected, checksummed);
    }
}

test "Address.toChecksummedHex - EIP-55 vs EIP-1191 difference" {
    // The same address produces different checksums depending on whether
    // chain_id is provided (EIP-1191) or not (EIP-55)

    const test_cases = [_]struct {
        input: []const u8,
        chain_id: ?u64,
        expected: []const u8,
    }{
        // Without chain_id: EIP-55 (all lowercase for this particular address)
        .{
            .input = "0x27b1fdb04752bbc536007a920d24acb045561c26",
            .chain_id = null,
            .expected = "0x27b1fdb04752bbc536007a920d24acb045561c26",
        },
        // With chain_id=1: EIP-1191 (different checksum!)
        .{
            .input = "0x27b1fdb04752bbc536007a920d24acb045561c26",
            .chain_id = 1,
            .expected = "0x27b1FdB04752bBc536007a920D24ACB045561c26",
        },
        // With chain_id=30: EIP-1191 (yet another different checksum!)
        .{
            .input = "0x27b1fdb04752bbc536007a920d24acb045561c26",
            .chain_id = 30,
            .expected = "0x27b1FdB04752BBc536007A920D24ACB045561c26",
        },
    };

    for (test_cases) |tc| {
        const addr = try Address.fromHex(tc.input);
        var buf: [42]u8 = undefined;
        const checksummed = try addr.toChecksummedHex(&buf, tc.chain_id);
        try expectEqualStrings(tc.expected, checksummed);
    }

    // Verify they're all different
    const addr = try Address.fromHex("0x27b1fdb04752bbc536007a920d24acb045561c26");
    var buf_eip55: [42]u8 = undefined;
    var buf_chain1: [42]u8 = undefined;
    var buf_chain30: [42]u8 = undefined;
    const eip55 = try addr.toChecksummedHex(&buf_eip55, null);
    const chain1 = try addr.toChecksummedHex(&buf_chain1, 1);
    const chain30 = try addr.toChecksummedHex(&buf_chain30, 30);
    try expect(!std.mem.eql(u8, eip55, chain1));
    try expect(!std.mem.eql(u8, eip55, chain30));
    try expect(!std.mem.eql(u8, chain1, chain30));
}

test "Address.fromChecksummedHex - EIP-1191 validation" {
    // Test checksum validation for EIP-1191, with all chains considered as opted-in.
    const test_cases = [_]struct {
        input: []const u8,
        chain_id: u64,
        should_succeed: bool,
    }{
        // Valid: EIP-1191 checksummed address for chain_id = 1
        .{
            .input = "0x27b1FdB04752bBc536007a920D24ACB045561c26",
            .chain_id = 1,
            .should_succeed = true,
        },
        // Valid: EIP-1191 checksummed address for RSK Mainnet (chain_id = 30)
        .{
            .input = "0x5aaEB6053f3e94c9b9a09f33669435E7ef1bEAeD",
            .chain_id = 30,
            .should_succeed = true,
        },
        // Valid: EIP-1191 checksummed address for RSK Testnet (chain_id = 31)
        .{
            .input = "0x5aAeb6053F3e94c9b9A09F33669435E7EF1BEaEd",
            .chain_id = 31,
            .should_succeed = true,
        },
        // Invalid: Using RSK Mainnet (chain_id=30) checksum for chain_id=1
        .{
            .input = "0x5aaEB6053f3e94c9b9a09f33669435E7ef1bEAeD",
            .chain_id = 1,
            .should_succeed = false,
        },
        // Invalid: Using RSK Testnet (chain_id=31) checksum for RSK Mainnet (chain_id=30)
        .{
            .input = "0x5aAeb6053F3e94c9b9A09F33669435E7EF1BEaEd",
            .chain_id = 30,
            .should_succeed = false,
        },
        // Invalid: Using chain_id=1 checksum for RSK Mainnet (chain_id=30)
        .{
            .input = "0x27b1FdB04752bBc536007a920D24ACB045561c26",
            .chain_id = 30,
            .should_succeed = false,
        },
        // Invalid: Using EIP-55 (no chain_id) checksum when chain_id is specified
        .{
            .input = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
            .chain_id = 1,
            .should_succeed = false,
        },
    };

    for (test_cases) |tc| {
        if (tc.should_succeed) {
            _ = try Address.fromChecksummedHex(tc.input, tc.chain_id);
        } else {
            try expectError(AddressError.InvalidChecksumFormat, Address.fromChecksummedHex(tc.input, tc.chain_id));
        }
    }
}

test "Address.fromHexComptime" {
    const test_cases = [_]struct {
        input: []const u8,
        expected_first: u8,
        expected_last: u8,
    }{
        // With 0x prefix
        .{
            .input = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
            .expected_first = 0xd8,
            .expected_last = 0x45,
        },
        // Without 0x prefix
        .{
            .input = "5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
            .expected_first = 0x5a,
            .expected_last = 0xed,
        },
        // All zeros
        .{
            .input = "0x0000000000000000000000000000000000000000",
            .expected_first = 0x00,
            .expected_last = 0x00,
        },
    };

    inline for (test_cases) |tc| {
        const addr = Address.fromHexComptime(tc.input);
        try expect(addr.inner.bytes[0] == tc.expected_first);
        try expect(addr.inner.bytes[19] == tc.expected_last);
    }
}

test "Address round-trip: hex -> Address -> hex" {
    const test_cases = [_][]const u8{
        "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
        "0x0000000000000000000000000000000000000000",
        "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed",
    };

    for (test_cases) |original| {
        const addr = try Address.fromHex(original);
        var buf: [42]u8 = undefined;
        const result = try addr.toHex(&buf);
        try expectEqualStrings(original, result);
    }
}

test "Address round-trip: checksummed hex -> Address -> checksummed hex" {
    const test_cases = [_][]const u8{
        "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
        "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
        "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
    };

    for (test_cases) |original| {
        const addr = try Address.fromChecksummedHex(original, null);
        var buf: [42]u8 = undefined;
        const result = try addr.toChecksummedHex(&buf, null);
        try expectEqualStrings(original, result);
    }
}

test "Address.format" {
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        // EIP-55 test vectors
        .{
            .input = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
            .expected = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
        },
        .{
            .input = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
            .expected = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
        },
        .{
            .input = "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
            .expected = "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
        },
        // All lowercase
        .{
            .input = "0xde709f2102306220921060314715629080e2fb77",
            .expected = "0xde709f2102306220921060314715629080e2fb77",
        },
        // All uppercase
        .{
            .input = "0x52908400098527886E0F7030069857D2E4169EE7",
            .expected = "0x52908400098527886E0F7030069857D2E4169EE7",
        },
    };

    for (test_cases) |tc| {
        const addr = try Address.fromHex(tc.input);

        // Test with bufPrint
        var buf: [100]u8 = undefined;
        const result = try std.fmt.bufPrint(&buf, "{f}", .{addr});
        try expectEqualStrings(tc.expected, result);

        // Test with bufPrint in a longer format string
        const result2 = try std.fmt.bufPrint(&buf, "Address: {f}", .{addr});
        var buf2: [100]u8 = undefined;
        const expected_with_prefix = try std.fmt.bufPrint(&buf2, "Address: {s}", .{tc.expected});
        try expectEqualStrings(expected_with_prefix, result2);

        // Test with allocPrint
        const allocator = std.testing.allocator;
        const result3 = try std.fmt.allocPrint(allocator, "{f}", .{addr});
        defer allocator.free(result3);
        try expectEqualStrings(tc.expected, result3);

        // Test with multiple addresses in format string
        const result4 = try std.fmt.allocPrint(allocator, "{f} and {f}", .{ addr, addr });
        defer allocator.free(result4);
        const expected_double = try std.fmt.allocPrint(allocator, "{s} and {s}", .{ tc.expected, tc.expected });
        defer allocator.free(expected_double);
        try expectEqualStrings(expected_double, result4);
    }
}
