const std = @import("std");

/// Errors that can occur when working with Ethereum addresses
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
    bytes: [20]u8,

    /// Initialize an address from a 20-byte array
    pub fn init(bytes: [20]u8) Address {
        return Address{ .bytes = bytes };
    }

    /// Parse an address from a hex string
    ///
    /// Accepts hex strings with or without "0x" prefix.
    /// The hex string must represent exactly 20 bytes (40 hex digits).
    ///
    /// This function does NOT validate EIP-55 checksums. Use `fromChecksummedHex`
    /// if you want to validate the checksum.
    ///
    /// Examples:
    /// - "0xd8da6bf26964af9d7eed9e03e53415d37aa96045" (with prefix)
    /// - "d8da6bf26964af9d7eed9e03e53415d37aa96045" (without prefix)
    /// - "0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045" (uppercase)
    pub fn fromHex(hex: []const u8) AddressError!Address {
        const start: usize = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X')) 2 else 0;
        const hex_digits = hex[start..];

        if (hex_digits.len != 40)
            return AddressError.InvalidHexStringLength;

        var bytes: [20]u8 = undefined;
        var i: usize = 0;
        while (i < 20) : (i += 1) {
            const hi = std.fmt.charToDigit(hex_digits[i * 2], 16) catch
                return AddressError.InvalidHexDigit;
            const lo = std.fmt.charToDigit(hex_digits[i * 2 + 1], 16) catch
                return AddressError.InvalidHexDigit;
            bytes[i] = (hi << 4) | lo;
        }

        return Address{ .bytes = bytes };
    }

    /// Parse an address from a checksummed hex string and validate the checksum
    ///
    /// Validates EIP-55 checksums (or EIP-1191 if chain_id is provided).
    /// Returns error if the checksum is invalid.
    ///
    /// For backward compatibility with pre-EIP-55 addresses, all-lowercase and
    /// all-uppercase addresses are accepted without checksum validation, as they
    /// cannot have a checksum encoded (checksums require mixed case).
    ///
    /// Parameters:
    /// - hex: The checksummed hex string (with or without "0x" prefix)
    /// - chain_id: Optional chain ID for EIP-1191 validation. If null, uses EIP-55.
    pub fn fromChecksummedHex(hex: []const u8, chain_id: ?u64) AddressError!Address {
        const start: usize = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X')) 2 else 0;
        const hex_digits = hex[start..];

        if (hex_digits.len != 40)
            return AddressError.InvalidHexStringLength;

        // Check if all lowercase or all uppercase (no checksum to validate)
        var has_lowercase = false;
        var has_uppercase = false;
        for (hex_digits) |c| {
            if (c >= 'a' and c <= 'f') has_lowercase = true;
            if (c >= 'A' and c <= 'F') has_uppercase = true;
        }

        // All lowercase or all uppercase = no checksum, just parse
        if (!has_lowercase or !has_uppercase) {
            return fromHex(hex);
        }

        // Mixed case = checksum must be valid
        // First, parse the address
        const addr = try fromHex(hex);

        // Validate the checksum
        if (!addr.validateChecksum(hex_digits, chain_id)) {
            return AddressError.InvalidChecksumFormat;
        }

        return addr;
    }

    /// Format address as a hex string (lowercase, with "0x" prefix)
    ///
    /// The output buffer must be at least 42 bytes (2 for "0x" + 40 for hex digits).
    ///
    /// Returns a slice of the buffer containing the formatted address.
    pub fn toHex(self: Address, buf: []u8) ![]const u8 {
        if (buf.len < 42) return error.BufferTooSmall;

        buf[0] = '0';
        buf[1] = 'x';

        var i: usize = 0;
        while (i < 20) : (i += 1) {
            const byte = self.bytes[i];
            buf[2 + i * 2] = std.fmt.digitToChar(byte >> 4, .lower);
            buf[2 + i * 2 + 1] = std.fmt.digitToChar(byte & 0x0F, .lower);
        }

        return buf[0..42];
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
    /// RSK Mainnet=30 and RSK Testnet=31). However, this implementation follows a
    /// simpler API: if chain_id is provided, EIP-1191 is used for ANY chain ID;
    /// if null, EIP-55 is used. This provides maximum flexibility for L2s and other
    /// chains that may want chain-specific checksums.
    ///
    /// The output buffer must be at least 42 bytes (2 for "0x" + 40 for hex digits).
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
        if (buf.len < 42) return error.BufferTooSmall;

        buf[0] = '0';
        buf[1] = 'x';

        // First, convert address to lowercase hex (without 0x prefix)
        var addr_hex: [40]u8 = undefined;
        var i: usize = 0;
        while (i < 20) : (i += 1) {
            const byte = self.bytes[i];
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

        // Apply checksum by capitalizing characters based on hash bits
        i = 0;
        while (i < 40) : (i += 1) {
            const c = addr_hex[i];
            // Only apply checksum to alphabetic characters (a-f)
            if (c >= 'a' and c <= 'f') {
                // Get the corresponding nibble from the hash
                const hash_byte = hash[i / 2];
                const nibble = if (i % 2 == 0) hash_byte >> 4 else hash_byte & 0x0F;

                // If the nibble's high bit is set (≥8), capitalize the character
                if (nibble >= 8) {
                    buf[2 + i] = c - 32; // Convert to uppercase
                } else {
                    buf[2 + i] = c;
                }
            } else {
                // Numeric character (0-9), no checksum
                buf[2 + i] = c;
            }
        }

        return buf[0..42];
    }

    /// Validate the checksum of a hex string against this address
    ///
    /// The hex string should be 40 characters (without "0x" prefix).
    /// Returns true if the checksum is valid, false otherwise.
    fn validateChecksum(self: Address, hex_digits: []const u8, chain_id: ?u64) bool {
        if (hex_digits.len != 40) return false;

        // Generate the expected checksummed version
        var expected_buf: [42]u8 = undefined;
        const expected = self.toChecksummedHex(&expected_buf, chain_id) catch return false;

        // Compare (skip "0x" prefix)
        var i: usize = 0;
        while (i < 40) : (i += 1) {
            if (hex_digits[i] != expected[2 + i]) return false;
        }

        return true;
    }

    /// Check if two addresses are equal
    pub fn eql(self: Address, other: Address) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }
};

/// Compile-time address creation from hex string
///
/// This function can only be used at compile time. It's useful for defining
/// constant addresses (e.g., precompile addresses, system contracts).
///
/// Example:
/// ```zig
/// const zero_address = address("0x0000000000000000000000000000000000000000");
/// ```
pub fn address(comptime hex: []const u8) Address {
    @setEvalBranchQuota(2000);
    const start = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X')) 2 else 0;
    const hex_digits = hex[start..];

    if (hex_digits.len != 40)
        @compileError("Address hex string must be 40 hex digits (20 bytes)");

    var bytes: [20]u8 = undefined;
    comptime var i: usize = 0;
    inline while (i < 20) : (i += 1) {
        const hi = std.fmt.charToDigit(hex_digits[i * 2], 16) catch unreachable;
        const lo = std.fmt.charToDigit(hex_digits[i * 2 + 1], 16) catch unreachable;
        bytes[i] = (hi << 4) | lo;
    }

    return Address{ .bytes = bytes };
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

test "Address.fromHex - valid addresses" {
    // With 0x prefix, lowercase
    const addr1 = try Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");
    try expect(addr1.bytes[0] == 0xd8);
    try expect(addr1.bytes[19] == 0x45);

    // Without 0x prefix
    const addr2 = try Address.fromHex("d8da6bf26964af9d7eed9e03e53415d37aa96045");
    try expect(addr2.bytes[0] == 0xd8);
    try expect(addr2.bytes[19] == 0x45);

    // Uppercase hex
    const addr3 = try Address.fromHex("0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045");
    try expect(addr3.bytes[0] == 0xD8);
    try expect(addr3.bytes[0] == 0xd8); // Same value
    try expect(addr3.bytes[19] == 0x45);

    // Mixed case
    const addr4 = try Address.fromHex("0xD8da6BF26964af9d7eed9e03e53415d37aa96045");
    try expect(addr4.bytes[0] == 0xD8);

    // All zeros
    const addr5 = try Address.fromHex("0x0000000000000000000000000000000000000000");
    try expect(addr5.bytes[0] == 0x00);
    try expect(addr5.bytes[19] == 0x00);

    // All ones
    const addr6 = try Address.fromHex("0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF");
    try expect(addr6.bytes[0] == 0xFF);
    try expect(addr6.bytes[19] == 0xFF);
}

test "Address.fromHex - invalid inputs" {
    // Too short
    try expectError(AddressError.InvalidHexStringLength, Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa9604"));

    // Too long
    try expectError(AddressError.InvalidHexStringLength, Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa9604500"));

    // Invalid character
    try expectError(AddressError.InvalidHexDigit, Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa9604z"));

    // Empty string
    try expectError(AddressError.InvalidHexStringLength, Address.fromHex(""));

    // Only 0x
    try expectError(AddressError.InvalidHexStringLength, Address.fromHex("0x"));
}

test "Address.toHex - basic formatting" {
    const addr = try Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");
    var buf: [42]u8 = undefined;
    const hex = try addr.toHex(&buf);

    try expectEqualStrings("0xd8da6bf26964af9d7eed9e03e53415d37aa96045", hex);
}

test "Address.toHex - zero address" {
    const addr = try Address.fromHex("0x0000000000000000000000000000000000000000");
    var buf: [42]u8 = undefined;
    const hex = try addr.toHex(&buf);

    try expectEqualStrings("0x0000000000000000000000000000000000000000", hex);
}

test "Address.eql" {
    const addr1 = try Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");
    const addr2 = try Address.fromHex("0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045");
    const addr3 = try Address.fromHex("0x0000000000000000000000000000000000000000");

    try expect(addr1.eql(addr2));
    try expect(!addr1.eql(addr3));
}

// Test vectors from EIP-55 specification
// Source: https://eips.ethereum.org/EIPS/eip-55
test "Address.toChecksummedHex - EIP-55 test vectors" {
    // Test vectors from EIP-55 (no chain ID = use EIP-55)
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
        // Mixed case - typical checksummed addresses
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
    // Valid checksummed addresses (should succeed)
    _ = try Address.fromChecksummedHex("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", null);
    _ = try Address.fromChecksummedHex("0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359", null);
    _ = try Address.fromChecksummedHex("0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB", null);

    // All lowercase (no checksum - should succeed)
    _ = try Address.fromChecksummedHex("0xde709f2102306220921060314715629080e2fb77", null);

    // All uppercase (no checksum - should succeed)
    _ = try Address.fromChecksummedHex("0x52908400098527886E0F7030069857D2E4169EE7", null);

    // Invalid checksum (should fail)
    try expectError(
        AddressError.InvalidChecksumFormat,
        Address.fromChecksummedHex("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD", null), // Last char should be 'd' not 'D'
    );
}

// Test vectors from EIP-1191 specification for opted-in chains
// Source: https://eips.ethereum.org/EIPS/eip-1191 (now at https://github.com/ethereum/ercs)
//
// NOTE: EIP-1191 was officially adopted only by RSK Mainnet (30) and RSK Testnet (31).
// This test verifies our implementation matches the official EIP-1191 test vectors
// for these opted-in chains.
test "Address.toChecksummedHex - EIP-1191 opted-in chains (30, 31)" {
    // Test vectors from ERC-1191 for RSK chains

    // Address 1: 0x27b1fdb04752bbc536007a920d24acb045561c26
    const addr1 = try Address.fromHex("0x27b1fdb04752bbc536007a920d24acb045561c26");

    // Chain ID 30 (RSK Mainnet) - official ERC-1191 test vector
    var buf1_chain30: [42]u8 = undefined;
    const checksummed1_chain30 = try addr1.toChecksummedHex(&buf1_chain30, 30);
    try expectEqualStrings("0x27b1FdB04752BBc536007A920D24ACB045561c26", checksummed1_chain30);

    // Chain ID 31 (RSK Testnet) - official ERC-1191 test vector
    var buf1_chain31: [42]u8 = undefined;
    const checksummed1_chain31 = try addr1.toChecksummedHex(&buf1_chain31, 31);
    try expectEqualStrings("0x27B1FdB04752BbC536007a920D24acB045561C26", checksummed1_chain31);

    // Address 2: 0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed
    const addr2 = try Address.fromHex("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");

    // Chain ID 30 (RSK Mainnet) - official ERC-1191 test vector
    var buf2_chain30: [42]u8 = undefined;
    const checksummed2_chain30 = try addr2.toChecksummedHex(&buf2_chain30, 30);
    try expectEqualStrings("0x5aaEB6053f3e94c9b9a09f33669435E7ef1bEAeD", checksummed2_chain30);

    // Chain ID 31 (RSK Testnet) - official ERC-1191 test vector
    var buf2_chain31: [42]u8 = undefined;
    const checksummed2_chain31 = try addr2.toChecksummedHex(&buf2_chain31, 31);
    try expectEqualStrings("0x5aAeb6053F3e94c9b9A09F33669435E7EF1BEaEd", checksummed2_chain31);

    // Address 3: 0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb
    const addr3 = try Address.fromHex("0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb");

    // Chain ID 30 (RSK Mainnet) - official ERC-1191 test vector
    var buf3_chain30: [42]u8 = undefined;
    const checksummed3_chain30 = try addr3.toChecksummedHex(&buf3_chain30, 30);
    try expectEqualStrings("0xD1220A0Cf47c7B9BE7a2e6ba89F429762E7B9adB", checksummed3_chain30);

    // Chain ID 31 (RSK Testnet) - official ERC-1191 test vector
    var buf3_chain31: [42]u8 = undefined;
    const checksummed3_chain31 = try addr3.toChecksummedHex(&buf3_chain31, 31);
    try expectEqualStrings("0xd1220a0CF47c7B9Be7A2E6Ba89f429762E7b9adB", checksummed3_chain31);

    // Address 4: 0x3599689E6292b81B2d85451025146515070129Bb
    const addr4 = try Address.fromHex("0x3599689E6292b81B2d85451025146515070129Bb");

    // Chain ID 30 (RSK Mainnet) - official ERC-1191 test vector
    var buf4_chain30: [42]u8 = undefined;
    const checksummed4_chain30 = try addr4.toChecksummedHex(&buf4_chain30, 30);
    try expectEqualStrings("0x3599689E6292B81B2D85451025146515070129Bb", checksummed4_chain30);

    // Chain ID 31 (RSK Testnet) - official ERC-1191 test vector
    var buf4_chain31: [42]u8 = undefined;
    const checksummed4_chain31 = try addr4.toChecksummedHex(&buf4_chain31, 31);
    try expectEqualStrings("0x3599689e6292b81b2D85451025146515070129Bb", checksummed4_chain31);
}

// Test EIP-1191 behavior for non-opted-in chains
// For chains that didn't officially adopt EIP-1191, our implementation still
// applies EIP-1191 when chain_id is provided (for flexibility with L2s).
test "Address.toChecksummedHex - EIP-1191 for non-opted-in chains" {
    // Address: 0x27b1fdb04752bbc536007a920d24acb045561c26
    const addr = try Address.fromHex("0x27b1fdb04752bbc536007a920d24acb045561c26");

    // Chain ID 1 (Ethereum Mainnet - not opted in to EIP-1191)
    // When chain_id is provided, we apply EIP-1191 algorithm
    var buf_chain1: [42]u8 = undefined;
    const checksummed_chain1 = try addr.toChecksummedHex(&buf_chain1, 1);
    // This is computed using EIP-1191 with chain_id=1
    // Hash input: "10x27b1fdb04752bbc536007a920d24acb045561c26"
    try expectEqualStrings("0x27b1FdB04752bBc536007a920D24ACB045561c26", checksummed_chain1);

    // Without chain_id (null), use EIP-55
    var buf_no_chain: [42]u8 = undefined;
    const checksummed_no_chain = try addr.toChecksummedHex(&buf_no_chain, null);
    // This matches the official EIP-55 test vector
    try expectEqualStrings("0x27b1fdb04752bbc536007a920d24acb045561c26", checksummed_no_chain);

    // Verify they're different
    try expect(!std.mem.eql(u8, checksummed_chain1, checksummed_no_chain));

    // Another example with chain_id=10 (Optimism - not opted in)
    var buf_chain10: [42]u8 = undefined;
    const checksummed_chain10 = try addr.toChecksummedHex(&buf_chain10, 10);
    // Computed using EIP-1191 with chain_id=10
    // Hash input: "100x27b1fdb04752bbc536007a920d24acb045561c26"
    try expectEqualStrings("0x27B1fDB04752BBC536007a920D24acB045561C26", checksummed_chain10);
}

// Test demonstrating the difference between EIP-55 and EIP-1191
// Source: Comparing our implementation behavior
test "Address.toChecksummedHex - EIP-55 vs EIP-1191 difference" {
    // The same address produces different checksums depending on whether
    // chain_id is provided (EIP-1191) or not (EIP-55)
    const addr = try Address.fromHex("0x27b1fdb04752bbc536007a920d24acb045561c26");

    // Without chain_id: EIP-55 (all lowercase for this particular address)
    var buf_eip55: [42]u8 = undefined;
    const eip55 = try addr.toChecksummedHex(&buf_eip55, null);
    try expectEqualStrings("0x27b1fdb04752bbc536007a920d24acb045561c26", eip55);

    // With chain_id=1: EIP-1191 (different checksum!)
    var buf_chain1: [42]u8 = undefined;
    const chain1 = try addr.toChecksummedHex(&buf_chain1, 1);
    try expectEqualStrings("0x27b1FdB04752bBc536007a920D24ACB045561c26", chain1);

    // With chain_id=30: EIP-1191 (yet another different checksum!)
    var buf_chain30: [42]u8 = undefined;
    const chain30 = try addr.toChecksummedHex(&buf_chain30, 30);
    try expectEqualStrings("0x27b1FdB04752BBc536007A920D24ACB045561c26", chain30);

    // Verify they're all different
    try expect(!std.mem.eql(u8, eip55, chain1));
    try expect(!std.mem.eql(u8, eip55, chain30));
    try expect(!std.mem.eql(u8, chain1, chain30));
}

// Test checksum validation for EIP-1191
test "Address.fromChecksummedHex - EIP-1191 validation" {
    // Valid: EIP-1191 checksummed address for chain_id = 1
    // Our implementation applies EIP-1191 when chain_id is provided
    _ = try Address.fromChecksummedHex("0x27b1FdB04752bBc536007a920D24ACB045561c26", 1);

    // Valid: EIP-1191 checksummed address for RSK Mainnet (chain_id = 30)
    _ = try Address.fromChecksummedHex("0x5aaEB6053f3e94c9b9a09f33669435E7ef1bEAeD", 30);

    // Valid: EIP-1191 checksummed address for RSK Testnet (chain_id = 31)
    _ = try Address.fromChecksummedHex("0x5aAeb6053F3e94c9b9A09F33669435E7EF1BEaEd", 31);

    // Invalid: Using RSK Mainnet (chain_id=30) checksum for chain_id=1
    // The same address checksums differently depending on chain ID
    try expectError(
        AddressError.InvalidChecksumFormat,
        Address.fromChecksummedHex("0x5aaEB6053f3e94c9b9a09f33669435E7ef1bEAeD", 1),
    );

    // Invalid: Using RSK Testnet (chain_id=31) checksum for RSK Mainnet (chain_id=30)
    try expectError(
        AddressError.InvalidChecksumFormat,
        Address.fromChecksummedHex("0x5aAeb6053F3e94c9b9A09F33669435E7EF1BEaEd", 30),
    );

    // Invalid: Using chain_id=1 checksum for RSK Mainnet (chain_id=30)
    try expectError(
        AddressError.InvalidChecksumFormat,
        Address.fromChecksummedHex("0x27b1FdB04752bBc536007a920D24ACB045561c26", 30),
    );

    // Invalid: Using EIP-55 (no chain_id) checksum when chain_id is specified
    // EIP-55 and EIP-1191 produce different checksums
    try expectError(
        AddressError.InvalidChecksumFormat,
        Address.fromChecksummedHex("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", 1),
    );
}

test "address() - compile-time address creation" {
    // Valid usage at comptime
    const addr = address("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");
    try expect(addr.bytes[0] == 0xd8);
    try expect(addr.bytes[19] == 0x45);

    // Without 0x prefix
    const addr2 = address("5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");
    try expect(addr2.bytes[0] == 0x5a);

    // All zeros
    const zero = address("0x0000000000000000000000000000000000000000");
    try expect(zero.bytes[0] == 0x00);
    try expect(zero.bytes[19] == 0x00);
}

test "Address round-trip: hex -> Address -> hex" {
    const original = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045";
    const addr = try Address.fromHex(original);
    var buf: [42]u8 = undefined;
    const result = try addr.toHex(&buf);
    try expectEqualStrings(original, result);
}

test "Address round-trip: checksummed hex -> Address -> checksummed hex" {
    const original = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed";
    const addr = try Address.fromChecksummedHex(original, null);
    var buf: [42]u8 = undefined;
    const result = try addr.toChecksummedHex(&buf, null);
    try expectEqualStrings(original, result);
}
