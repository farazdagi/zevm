//! Bytecode analysis and parsing module.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Opcode = @import("opcode.zig").Opcode;
const Address = @import("../primitives/address.zig").Address;
const JumpTable = @import("JumpTable.zig");

/// Regular EVM bytecode that has been analyzed for valid JUMPDEST positions.
pub const AnalyzedBytecode = struct {
    /// Allocator used for memory management.
    allocator: Allocator,

    /// Jump table with valid JUMPDEST positions.
    jump_table: JumpTable,

    /// Raw bytecode bytes (owned allocation).
    raw: []u8,

    /// Analyze bytecode with jump table caching.
    ///
    /// Takes ownership of the bytecode parameter.
    ///
    /// Checks cache for existing analysis by code hash.
    /// On cache miss, stores the analysis for future reuse.
    ///
    /// Returns AnalyzedBytecode where valid JUMPDEST positions can be queried in O(1).
    pub fn init(
        allocator: Allocator,
        bytecode: []u8,
        cache: *JumpTable.Cache,
    ) !AnalyzedBytecode {
        const code_hash = JumpTable.computeCodeHash(bytecode);

        const jump_table = if (cache.get(code_hash)) |cached| blk: {
            // Cache hit - clone for ownership.
            break :blk try cached.clone(allocator);
        } else blk: {
            // Cache miss - analyze and store.
            var analyzed = try JumpTable.analyze(allocator, bytecode);
            errdefer analyzed.deinit();

            // Save cloned table for re-use.
            var for_cache = try analyzed.clone(allocator);
            errdefer for_cache.deinit();
            try cache.put(code_hash, for_cache);

            break :blk analyzed;
        };

        return .{
            .allocator = allocator,
            .jump_table = jump_table,
            .raw = bytecode,
        };
    }

    /// Analyze bytecode without caching.
    ///
    /// Takes ownership of the bytecode parameter.
    ///
    /// Use this for tests or one-off analysis where caching is not necessary.
    /// For production code, use init() with cache.
    pub fn initUncached(allocator: Allocator, bytecode: []u8) !AnalyzedBytecode {
        const jump_table = try JumpTable.analyze(allocator, bytecode);

        return .{
            .allocator = allocator,
            .jump_table = jump_table,
            .raw = bytecode,
        };
    }

    /// Check if a position is a valid jump destination.
    ///
    /// Returns true if the position points to a JUMPDEST opcode,
    /// false if out of bounds or not a JUMPDEST.
    pub fn isValidJump(self: *const AnalyzedBytecode, dest: usize) bool {
        return self.jump_table.isValidDest(dest);
    }

    /// Get bytecode length.
    pub fn len(self: *const AnalyzedBytecode) usize {
        return self.raw.len;
    }

    /// Free allocated resources.
    pub fn deinit(self: AnalyzedBytecode) void {
        self.jump_table.deinit();
        self.allocator.free(self.raw);
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
    /// Allocator used for memory management (null for borrowed references).
    allocator: ?Allocator,

    /// Delegation target address
    delegated_address: Address,

    /// Version byte (currently only 0 is valid)
    version: u8,

    /// Raw 23-byte delegation indicator with ownership semantics.
    raw: union(enum) {
        /// Owned allocation (must be freed).
        owned: []u8,
        /// Borrowed reference (must not be freed).
        borrowed: []const u8,
    },

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
            .allocator = null,
            .delegated_address = delegated_address,
            .version = version,
            .raw = .{ .borrowed = raw },
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
            .allocator = allocator,
            .delegated_address = address,
            .version = VERSION,
            .raw = .{ .owned = raw },
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
        return switch (self.raw) {
            .owned => |bytes| bytes.len,
            .borrowed => |bytes| bytes.len,
        };
    }

    /// Free allocated resources.
    pub fn deinit(self: *Eip7702Bytecode) void {
        switch (self.raw) {
            .owned => |bytes| {
                if (self.allocator) |alloc| {
                    alloc.free(bytes);
                }
            },
            .borrowed => {}, // Borrowed reference, no need to free
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
    /// Takes ownership of the bytecode parameter. Detects bytecode format based
    /// on magic bytes:
    /// - 0xEF01: EIP-7702 delegation
    /// - Other: Regular bytecode (performs JUMPDEST analysis)
    ///
    /// Uses cache for jump table analysis by code hash.
    pub fn analyze(allocator: Allocator, raw: []u8, cache: *JumpTable.Cache) !Bytecode {
        // Detect EIP-7702 delegation format
        if (raw.len >= 2) {
            const magic = std.mem.readInt(u16, raw[0..2], .big);

            // EIP-7702 delegation (0xEF01)
            if (magic == 0xEF01) {
                // Parse and validate, then store as owned
                const parsed = try Eip7702Bytecode.parse(raw);
                return Bytecode{
                    .eip7702 = .{
                        .allocator = allocator,
                        .delegated_address = parsed.delegated_address,
                        .version = parsed.version,
                        .raw = .{ .owned = raw }, // Take ownership
                    },
                };
            }
        }

        // Default: Regular bytecode (perform JUMPDEST analysis)
        return Bytecode{ .analyzed = try AnalyzedBytecode.init(allocator, raw, cache) };
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
    /// Takes ownership of bytecode_data. Convenience constructor for creating
    /// analyzed bytecode when you know the format is not EIP-7702. Performs
    /// JUMPDEST analysis.
    ///
    /// Uses cache for jump table analysis by code hash.
    pub fn newAnalyzed(allocator: Allocator, bytecode_data: []u8, cache: *JumpTable.Cache) !Bytecode {
        const analyzed = try AnalyzedBytecode.init(allocator, bytecode_data, cache);
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
            .eip7702 => |b| switch (b.raw) {
                .owned => |bytes| bytes,
                .borrowed => |bytes| bytes,
            },
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
    pub fn deinit(self: *Bytecode) void {
        switch (self.*) {
            .analyzed => |*b| b.deinit(),
            .eip7702 => |*b| b.deinit(),
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

/// Allocate bytecode on heap from stack array.
///
/// Mimics the behavior of host.code() which returns heap-allocated bytecode.
/// Ownership is transferred to the caller.
fn makeTestBytecode(allocator: Allocator, code: []const u8) ![]u8 {
    return allocator.dupe(u8, code);
}

test "AnalyzedBytecode: basic analysis" {
    // PUSH1 0x05, JUMP, INVALID, INVALID, JUMPDEST, STOP
    var analysis = try AnalyzedBytecode.initUncached(
        std.testing.allocator,
        try makeTestBytecode(std.testing.allocator, &[_]u8{ 0x60, 0x05, 0x56, 0xFE, 0xFE, 0x5B, 0x00 }),
    );
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
    var analysis = try AnalyzedBytecode.initUncached(
        std.testing.allocator,
        try makeTestBytecode(std.testing.allocator, &[_]u8{ 0x61, 0x5B, 0x5B, 0x5B }),
    );
    defer analysis.deinit();

    // Only position 3 is a real JUMPDEST
    try expect(!analysis.isValidJump(1)); // Inside PUSH2 immediate
    try expect(!analysis.isValidJump(2)); // Inside PUSH2 immediate
    try expect(analysis.isValidJump(3)); // Real JUMPDEST
}

test "AnalyzedBytecode: multiple JUMPDESTs" {
    // JUMPDEST, PUSH1 0x05, JUMPDEST, PUSH1 0x00, JUMPDEST
    var analysis = try AnalyzedBytecode.initUncached(
        std.testing.allocator,
        try makeTestBytecode(std.testing.allocator, &[_]u8{ 0x5B, 0x60, 0x05, 0x5B, 0x60, 0x00, 0x5B }),
    );
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
    var bytecode_stack: [34]u8 = undefined;
    bytecode_stack[0] = 0x7F; // PUSH32
    // Fill with fake JUMPDEST bytes
    for (0..32) |i| {
        bytecode_stack[1 + i] = 0x5B;
    }
    bytecode_stack[33] = 0x5B; // Real JUMPDEST

    var analysis = try AnalyzedBytecode.initUncached(
        std.testing.allocator,
        try makeTestBytecode(std.testing.allocator, &bytecode_stack),
    );
    defer analysis.deinit();

    // Only position 33 is valid (after PUSH32 and its 32 immediate bytes)
    for (0..33) |i| {
        try expect(!analysis.isValidJump(i));
    }
    try expect(analysis.isValidJump(33));
}

test "AnalyzedBytecode: empty bytecode" {
    var analysis = try AnalyzedBytecode.initUncached(
        std.testing.allocator,
        try makeTestBytecode(std.testing.allocator, &[_]u8{}),
    );
    defer analysis.deinit();

    // No valid destinations in empty bytecode
    try expect(!analysis.isValidJump(0));
}

test "AnalyzedBytecode: out of bounds" {
    var analysis = try AnalyzedBytecode.initUncached(
        std.testing.allocator,
        try makeTestBytecode(std.testing.allocator, &[_]u8{ 0x5B, 0x00 }),
    );
    defer analysis.deinit();

    try expect(analysis.isValidJump(0));
    try expect(!analysis.isValidJump(2)); // Out of bounds
    try expect(!analysis.isValidJump(100)); // Way out of bounds
}

test "Bytecode: format detection - regular bytecode" {
    var cache = JumpTable.Cache.init(std.testing.allocator);
    defer {
        var it = cache.valueIterator();
        while (it.next()) |jt| jt.deinit();
        cache.deinit();
    }

    var bc = try Bytecode.analyze(
        std.testing.allocator,
        try makeTestBytecode(std.testing.allocator, &[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }),
        &cache,
    );
    defer bc.deinit();

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
    try expectEqual(23, eip7702.len());
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
    defer eip7702.deinit();

    try expectEqual(Eip7702Bytecode.VERSION, eip7702.version);
    try expectEqual(23, eip7702.len());
    try expect(addr.eql(eip7702.delegated_address));

    // Verify format (extract bytes from union)
    const bytes = switch (eip7702.raw) {
        .owned => |b| b,
        .borrowed => |b| b,
    };
    try expectEqual(0xEF, bytes[0]);
    try expectEqual(0x01, bytes[1]);
    try expectEqual(0x00, bytes[2]);
}

test "Eip7702Bytecode: zero address (cleared delegation)" {
    const zero_addr = Address.zero();

    var eip7702 = try Eip7702Bytecode.new(std.testing.allocator, zero_addr);
    defer eip7702.deinit();

    try expect(eip7702.isCleared());
}

test "Bytecode: auto-detect EIP-7702" {
    var cache = JumpTable.Cache.init(std.testing.allocator);
    defer cache.deinit(); // No entries for EIP-7702 (returns early)

    const addr = try Address.fromHex("0xABCDEF0123456789ABCDEF0123456789ABCDEF01");

    // Create delegation bytecode
    var delegation = try Eip7702Bytecode.new(std.testing.allocator, addr);

    // Duplicate the bytes so both delegation and Bytecode can own their copies
    const raw_bytes = switch (delegation.raw) {
        .owned => |b| b,
        .borrowed => |b| b,
    };
    const bytecode_copy = try std.testing.allocator.dupe(u8, raw_bytes);

    // Clean up delegation (we only needed it to create the bytes)
    delegation.deinit();

    // Analyze should detect EIP-7702 format
    var bc = try Bytecode.analyze(std.testing.allocator, bytecode_copy, &cache);
    defer bc.deinit();

    try expect(bc.isEip7702());
    try expect(!bc.isAnalyzed());
}

test "Bytecode: newDelegation convenience constructor" {
    const addr = try Address.fromHex("0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF");

    var bc = try Bytecode.newDelegation(std.testing.allocator, addr);
    defer bc.deinit();

    try expect(bc.isEip7702());
    try expectEqual(23, bc.len());

    // Verify we can access the delegation
    const eip7702 = bc.eip7702;
    try expect(addr.eql(eip7702.delegated_address));
}

test "Bytecode: newAnalyzed convenience constructor" {
    var cache = JumpTable.Cache.init(std.testing.allocator);
    defer {
        var it = cache.valueIterator();
        while (it.next()) |jt| jt.deinit();
        cache.deinit();
    }

    var bc = try Bytecode.newAnalyzed(
        std.testing.allocator,
        try makeTestBytecode(std.testing.allocator, &[_]u8{ 0x5B, 0x60, 0x01, 0x5B }),
        &cache,
    );
    defer bc.deinit();

    try expect(bc.isAnalyzed());
    try expect(!bc.isEip7702());

    // Verify JUMPDEST analysis was performed
    const analyzed = bc.analyzed;
    try expect(analyzed.isValidJump(0));
    try expect(!analyzed.isValidJump(1));
    try expect(!analyzed.isValidJump(2));
    try expect(analyzed.isValidJump(3));
}
