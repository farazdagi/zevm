//! Bytecode analysis and parsing module.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Opcode = @import("opcode.zig").Opcode;
const Address = @import("../primitives/address.zig").Address;

/// Regular EVM bytecode that has been analyzed for valid JUMPDEST positions.
pub const AnalyzedBytecode = struct {
    /// Bitmap of valid JUMPDEST positions (1 bit per bytecode position)
    jumpdests: std.DynamicBitSet,

    /// Raw bytecode bytes
    raw: []const u8,

    /// Analyze bytecode to find all valid JUMPDEST positions.
    ///
    /// Returns AnalyzedBytecode with a bitmap where bit N is set if position N
    /// is a valid JUMPDEST opcode. PUSH immediate data is correctly skipped.
    pub fn analyze(allocator: Allocator, bytecode: []const u8) !AnalyzedBytecode {
        var jumpdests = try std.DynamicBitSet.initEmpty(allocator, bytecode.len);
        errdefer jumpdests.deinit();

        var i: usize = 0;
        while (i < bytecode.len) {
            const opcode = Opcode.fromByte(bytecode[i]) catch {
                // Invalid opcode - skip and continue
                i += 1;
                continue;
            };

            if (opcode == .JUMPDEST) {
                jumpdests.set(i);
            }

            // If PUSH opcode, also skip immediate data
            i += if (opcode.isPush()) 1 + opcode.pushSize() else 1;
        }

        return .{
            .jumpdests = jumpdests,
            .raw = bytecode,
        };
    }

    /// Check if a position is a valid jump destination.
    ///
    /// Returns true if the position points to a JUMPDEST opcode,
    /// false if out of bounds or not a JUMPDEST.
    pub fn isValidJump(self: *const AnalyzedBytecode, dest: usize) bool {
        if (dest >= self.jumpdests.capacity()) return false;
        return self.jumpdests.isSet(dest);
    }

    /// Get bytecode length.
    pub fn len(self: *const AnalyzedBytecode) usize {
        return self.raw.len;
    }

    /// Free allocated resources.
    pub fn deinit(self: *AnalyzedBytecode) void {
        self.jumpdests.deinit();
    }
};

/// EIP-7702 delegation bytecode.
///
/// Format: 0xEF01 || version(1 byte) || address(20 bytes) = 23 bytes total
///
/// This bytecode format allows an EOA to delegate execution to a contract
/// address for the duration of a transaction, enabling account abstraction features.
///
/// The delegation indicator is set by transaction type 0x04 with an authorization
/// list. When encountered during execution, the EVM loads code from the delegated
/// address and executes it in the authority's context (DELEGATECALL semantics).
///
/// Reference: https://eips.ethereum.org/EIPS/eip-7702
pub const Eip7702Bytecode = struct {
    /// Delegation target address
    delegated_address: Address,

    /// Version byte (currently only 0 is valid)
    version: u8,

    /// Raw 23-byte delegation indicator
    raw: []const u8,

    /// Whether this instance owns the raw bytes and should free them on deinit
    owns_memory: bool,

    /// Magic bytes (0xEF01)
    pub const MAGIC: u16 = 0xEF01;

    /// Current version (only 0 is valid)
    pub const VERSION: u8 = 0x00;

    /// Expected total length
    pub const LENGTH: usize = 23;

    /// Errors that can occur during parsing
    pub const Error = error{
        InvalidLength,
        InvalidMagic,
        UnsupportedVersion,
    };

    /// Parse EIP-7702 delegation bytecode from raw bytes.
    ///
    /// Validates format and extracts the delegated address.
    ///
    /// Returns error if:
    /// - Length is not exactly 23 bytes
    /// - Magic bytes are not 0xEF01
    /// - Version is not 0x00
    ///
    /// Note: This function does NOT allocate memory - it stores a reference
    /// to the input slice. The caller must ensure the slice remains valid
    /// for the lifetime of the returned Eip7702Bytecode.
    pub fn parse(raw: []const u8) !Eip7702Bytecode {
        if (raw.len != LENGTH) return error.InvalidLength;

        const magic = std.mem.readInt(u16, raw[0..2], .big);
        if (magic != MAGIC) return error.InvalidMagic;

        const version = raw[2];
        if (version != VERSION) return error.UnsupportedVersion;

        // Extract address bytes (20 bytes starting at position 3)
        var addr_bytes: [20]u8 = undefined;
        @memcpy(&addr_bytes, raw[3..23]);
        const delegated_address = Address.init(addr_bytes);

        return .{
            .delegated_address = delegated_address,
            .version = version,
            .raw = raw,
            .owns_memory = false, // parse() does not allocate
        };
    }

    /// Create delegation bytecode from an address.
    ///
    /// Constructs the 23-byte delegation indicator (0xEF01 || 0x00 || address).
    /// The caller owns the allocated memory and must free it.
    pub fn new(allocator: Allocator, address: Address) !Eip7702Bytecode {
        var raw = try allocator.alloc(u8, LENGTH);
        errdefer allocator.free(raw);

        // Write magic bytes
        std.mem.writeInt(u16, raw[0..2], MAGIC, .big);

        // Write version
        raw[2] = VERSION;

        // Write address
        @memcpy(raw[3..23], &address.inner.bytes);

        return .{
            .delegated_address = address,
            .version = VERSION,
            .raw = raw,
            .owns_memory = true, // new() allocates memory
        };
    }

    /// Check if delegation is cleared (delegated to zero address).
    ///
    /// A delegation to the zero address clears the delegation, resetting the
    /// account's code to empty.
    pub fn isCleared(self: *const Eip7702Bytecode) bool {
        return self.delegated_address.isZero();
    }

    /// Get bytecode length (always 23 bytes).
    pub fn len(self: *const Eip7702Bytecode) usize {
        return self.raw.len;
    }

    /// Free allocated resources.
    pub fn deinit(self: *Eip7702Bytecode, allocator: Allocator) void {
        if (self.owns_memory) {
            allocator.free(self.raw);
        }
    }
};

/// Bytecode after parsing/analysis.
///
/// Represents bytecode that has been parsed and is ready for use.
/// The format is detected automatically by `analyze()`.
pub const Bytecode = union(enum) {
    /// Analyzed EVM bytecode with JUMPDEST positions computed.
    analyzed: AnalyzedBytecode,

    /// EIP-7702 delegation bytecode.
    eip7702: Eip7702Bytecode,

    /// Analyze raw bytecode and return appropriate format.
    ///
    /// Detects bytecode format based on magic bytes:
    /// - 0xEF01: EIP-7702 delegation
    /// - Other: Regular bytecode (performs JUMPDEST analysis)
    pub fn analyze(allocator: Allocator, raw: []const u8) !Bytecode {
        // Detect EIP-7702 delegation format
        if (raw.len >= 2) {
            const magic = std.mem.readInt(u16, raw[0..2], .big);

            // EIP-7702 delegation (0xEF01)
            if (magic == 0xEF01) {
                return Bytecode{ .eip7702 = try Eip7702Bytecode.parse(raw) };
            }
        }

        // Default: Regular bytecode (perform JUMPDEST analysis)
        return Bytecode{ .analyzed = try AnalyzedBytecode.analyze(allocator, raw) };
    }

    /// Create EIP-7702 delegation bytecode from an address.
    ///
    /// Convenience constructor for creating delegation bytecode.
    pub fn newDelegation(allocator: Allocator, address: Address) !Bytecode {
        const eip7702 = try Eip7702Bytecode.new(allocator, address);
        return .{ .eip7702 = eip7702 };
    }

    /// Create analyzed bytecode from raw code.
    ///
    /// Convenience constructor for creating analyzed bytecode when you know
    /// the format is not EIP-7702. Performs JUMPDEST analysis.
    pub fn newAnalyzed(allocator: Allocator, bytecode_data: []const u8) !Bytecode {
        const analyzed = try AnalyzedBytecode.analyze(allocator, bytecode_data);
        return .{ .analyzed = analyzed };
    }

    /// Get raw bytecode slice for execution.
    ///
    /// Returns the bytecode bytes that should be executed by the interpreter.
    /// For EIP-7702, this is the 23-byte delegation indicator (actual code resolution happens
    /// at the Host/State layer).
    pub inline fn code(self: *const Bytecode) []const u8 {
        return switch (self.*) {
            .analyzed => |b| b.raw,
            .eip7702 => |b| b.raw,
        };
    }

    /// Get bytecode length in bytes.
    pub fn len(self: *const Bytecode) usize {
        return switch (self.*) {
            .analyzed => |b| b.len(),
            .eip7702 => |b| b.len(),
        };
    }

    /// Check if this is analyzed bytecode.
    pub fn isAnalyzed(self: *const Bytecode) bool {
        return self.* == .analyzed;
    }

    /// Check if this is EIP-7702 delegation.
    pub fn isEip7702(self: *const Bytecode) bool {
        return self.* == .eip7702;
    }

    /// Free allocated resources.
    pub fn deinit(self: *Bytecode, allocator: Allocator) void {
        switch (self.*) {
            .analyzed => |*b| b.deinit(),
            .eip7702 => |*b| b.deinit(allocator),
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "AnalyzedBytecode: basic analysis" {
    // PUSH1 0x05, JUMP, INVALID, INVALID, JUMPDEST, STOP
    const bytecode = [_]u8{ 0x60, 0x05, 0x56, 0xFE, 0xFE, 0x5B, 0x00 };

    var analysis = try AnalyzedBytecode.analyze(std.testing.allocator, &bytecode);
    defer analysis.deinit();

    // Position 5 is JUMPDEST
    try expect(analysis.isValidJump(5));

    // Other positions are not valid JUMPDEST
    try expect(!analysis.isValidJump(0)); // PUSH1
    try expect(!analysis.isValidJump(1)); // PUSH1 immediate data
    try expect(!analysis.isValidJump(2)); // JUMP
    try expect(!analysis.isValidJump(3)); // INVALID
    try expect(!analysis.isValidJump(4)); // INVALID
    try expect(!analysis.isValidJump(6)); // STOP
}

test "AnalyzedBytecode: skip PUSH immediate data" {
    // PUSH2 0x5B5B (fake JUMPDESTs in immediate), JUMPDEST
    const bytecode = [_]u8{ 0x61, 0x5B, 0x5B, 0x5B };

    var analysis = try AnalyzedBytecode.analyze(std.testing.allocator, &bytecode);
    defer analysis.deinit();

    // Only position 3 is a real JUMPDEST
    try expect(!analysis.isValidJump(1)); // Inside PUSH2 immediate
    try expect(!analysis.isValidJump(2)); // Inside PUSH2 immediate
    try expect(analysis.isValidJump(3)); // Real JUMPDEST
}

test "AnalyzedBytecode: multiple JUMPDESTs" {
    // JUMPDEST, PUSH1 0x05, JUMPDEST, PUSH1 0x00, JUMPDEST
    const bytecode = [_]u8{ 0x5B, 0x60, 0x05, 0x5B, 0x60, 0x00, 0x5B };

    var analysis = try AnalyzedBytecode.analyze(std.testing.allocator, &bytecode);
    defer analysis.deinit();

    // Positions 0, 3, 6 are JUMPDESTs
    try expect(analysis.isValidJump(0));
    try expect(analysis.isValidJump(3));
    try expect(analysis.isValidJump(6));

    // Other positions are not
    try expect(!analysis.isValidJump(1)); // PUSH1
    try expect(!analysis.isValidJump(2)); // PUSH1 immediate
    try expect(!analysis.isValidJump(4)); // PUSH1
    try expect(!analysis.isValidJump(5)); // PUSH1 immediate
}

test "AnalyzedBytecode: PUSH32 with fake JUMPDEST" {
    // PUSH32 followed by 32 bytes of 0x5B (JUMPDEST byte), then real JUMPDEST
    var bytecode: [34]u8 = undefined;
    bytecode[0] = 0x7F; // PUSH32
    // Fill with fake JUMPDEST bytes
    for (0..32) |i| {
        bytecode[1 + i] = 0x5B;
    }
    bytecode[33] = 0x5B; // Real JUMPDEST

    var analysis = try AnalyzedBytecode.analyze(std.testing.allocator, &bytecode);
    defer analysis.deinit();

    // Only position 33 is valid (after PUSH32 and its 32 immediate bytes)
    for (0..33) |i| {
        try expect(!analysis.isValidJump(i));
    }
    try expect(analysis.isValidJump(33));
}

test "AnalyzedBytecode: empty bytecode" {
    const bytecode = [_]u8{};

    var analysis = try AnalyzedBytecode.analyze(std.testing.allocator, &bytecode);
    defer analysis.deinit();

    // No valid destinations in empty bytecode
    try expect(!analysis.isValidJump(0));
}

test "AnalyzedBytecode: out of bounds" {
    const bytecode = [_]u8{ 0x5B, 0x00 }; // JUMPDEST, STOP

    var analysis = try AnalyzedBytecode.analyze(std.testing.allocator, &bytecode);
    defer analysis.deinit();

    try expect(analysis.isValidJump(0));
    try expect(!analysis.isValidJump(2)); // Out of bounds
    try expect(!analysis.isValidJump(100)); // Way out of bounds
}

test "Bytecode: format detection - regular bytecode" {
    const bytecode = [_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }; // PUSH1 1, PUSH1 2, ADD

    var bc = try Bytecode.analyze(std.testing.allocator, &bytecode);
    defer bc.deinit(std.testing.allocator);

    try expect(bc.isAnalyzed());
    try expect(!bc.isEip7702());
}

test "Eip7702Bytecode: parse valid delegation" {
    // Construct 23-byte delegation: 0xEF01 || 0x00 || address
    var raw: [23]u8 = undefined;
    raw[0] = 0xEF;
    raw[1] = 0x01;
    raw[2] = 0x00; // version
    // Fill with test address (0x1234...5678)
    for (0..20) |i| {
        raw[3 + i] = @intCast((i % 255) + 1);
    }

    const eip7702 = try Eip7702Bytecode.parse(&raw);

    try expectEqual(Eip7702Bytecode.VERSION, eip7702.version);
    try expectEqual(@as(usize, 23), eip7702.len());
    try expect(!eip7702.isCleared());
}

test "Eip7702Bytecode: parse invalid length" {
    const raw = [_]u8{ 0xEF, 0x01, 0x00 }; // Only 3 bytes

    const result = Eip7702Bytecode.parse(&raw);
    try expectError(error.InvalidLength, result);
}

test "Eip7702Bytecode: parse invalid magic" {
    var raw: [23]u8 = undefined;
    raw[0] = 0xEF;
    raw[1] = 0x00; // Wrong magic (should be 0xEF01, not 0xEF00)
    raw[2] = 0x00;

    const result = Eip7702Bytecode.parse(&raw);
    try expectError(error.InvalidMagic, result);
}

test "Eip7702Bytecode: parse unsupported version" {
    var raw: [23]u8 = undefined;
    raw[0] = 0xEF;
    raw[1] = 0x01;
    raw[2] = 0x01; // Version 1 (unsupported, only 0 is valid)

    const result = Eip7702Bytecode.parse(&raw);
    try expectError(error.UnsupportedVersion, result);
}

test "Eip7702Bytecode: create from address" {
    const addr = try Address.fromHex("0x1234567890123456789012345678901234567890");

    var eip7702 = try Eip7702Bytecode.new(std.testing.allocator, addr);
    defer eip7702.deinit(std.testing.allocator);

    try expectEqual(Eip7702Bytecode.VERSION, eip7702.version);
    try expectEqual(@as(usize, 23), eip7702.len());
    try expect(addr.eql(eip7702.delegated_address));

    // Verify format
    try expectEqual(@as(u8, 0xEF), eip7702.raw[0]);
    try expectEqual(@as(u8, 0x01), eip7702.raw[1]);
    try expectEqual(@as(u8, 0x00), eip7702.raw[2]);
}

test "Eip7702Bytecode: zero address (cleared delegation)" {
    const zero_addr = Address.zero();

    var eip7702 = try Eip7702Bytecode.new(std.testing.allocator, zero_addr);
    defer eip7702.deinit(std.testing.allocator);

    try expect(eip7702.isCleared());
}

test "Bytecode: auto-detect EIP-7702" {
    const addr = try Address.fromHex("0xABCDEF0123456789ABCDEF0123456789ABCDEF01");

    var delegation = try Eip7702Bytecode.new(std.testing.allocator, addr);
    defer delegation.deinit(std.testing.allocator);

    // Parse the delegation bytecode
    var bc = try Bytecode.analyze(std.testing.allocator, delegation.raw);
    defer bc.deinit(std.testing.allocator);

    try expect(bc.isEip7702());
    try expect(!bc.isAnalyzed());
}

test "Bytecode: newDelegation convenience constructor" {
    const addr = try Address.fromHex("0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF");

    var bc = try Bytecode.newDelegation(std.testing.allocator, addr);
    defer bc.deinit(std.testing.allocator);

    try expect(bc.isEip7702());
    try expectEqual(@as(usize, 23), bc.len());

    // Verify we can access the delegation
    const eip7702 = bc.eip7702;
    try expect(addr.eql(eip7702.delegated_address));
}

test "Bytecode: newAnalyzed convenience constructor" {
    const code = [_]u8{ 0x5B, 0x60, 0x01, 0x5B }; // JUMPDEST, PUSH1 1, JUMPDEST

    var bc = try Bytecode.newAnalyzed(std.testing.allocator, &code);
    defer bc.deinit(std.testing.allocator);

    try expect(bc.isAnalyzed());
    try expect(!bc.isEip7702());

    // Verify JUMPDEST analysis was performed
    const analyzed = bc.analyzed;
    try expect(analyzed.isValidJump(0));
    try expect(!analyzed.isValidJump(1));
    try expect(!analyzed.isValidJump(2));
    try expect(analyzed.isValidJump(3));
}
