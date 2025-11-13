//! EVM Opcode definitions and metadata.
//!
//! Reference: https://www.evm.codes/

const std = @import("std");
const Spec = @import("../hardfork.zig").Spec;

/// EVM Opcode.
///
/// Each opcode is mapped to its exact byte value as defined in the EVM spec.
pub const Opcode = enum(u8) {
    /// Opcode errors.
    pub const Error = error{
        /// The byte value does not correspond to a valid EVM opcode.
        InvalidOpcode,
    };

    // 0x0: Stop and Arithmetic Operations
    STOP = 0x00,
    ADD = 0x01,
    MUL = 0x02,
    SUB = 0x03,
    DIV = 0x04,
    SDIV = 0x05,
    MOD = 0x06,
    SMOD = 0x07,
    ADDMOD = 0x08,
    MULMOD = 0x09,
    EXP = 0x0A,
    SIGNEXTEND = 0x0B,

    // 0x10: Comparison & Bitwise Logic Operations
    LT = 0x10,
    GT = 0x11,
    SLT = 0x12,
    SGT = 0x13,
    EQ = 0x14,
    ISZERO = 0x15,
    AND = 0x16,
    OR = 0x17,
    XOR = 0x18,
    NOT = 0x19,
    BYTE = 0x1A,
    SHL = 0x1B,
    SHR = 0x1C,
    SAR = 0x1D,

    // 0x20: Cryptographic Operations
    KECCAK256 = 0x20,

    // 0x30: Environmental Information
    ADDRESS = 0x30,
    BALANCE = 0x31,
    ORIGIN = 0x32,
    CALLER = 0x33,
    CALLVALUE = 0x34,
    CALLDATALOAD = 0x35,
    CALLDATASIZE = 0x36,
    CALLDATACOPY = 0x37,
    CODESIZE = 0x38,
    CODECOPY = 0x39,
    GASPRICE = 0x3A,
    EXTCODESIZE = 0x3B,
    EXTCODECOPY = 0x3C,
    RETURNDATASIZE = 0x3D,
    RETURNDATACOPY = 0x3E,
    EXTCODEHASH = 0x3F,

    // 0x40: Block Information
    BLOCKHASH = 0x40,
    COINBASE = 0x41,
    TIMESTAMP = 0x42,
    NUMBER = 0x43,
    PREVRANDAO = 0x44, // DIFFICULTY pre-merge
    GASLIMIT = 0x45,
    CHAINID = 0x46,
    SELFBALANCE = 0x47,
    BASEFEE = 0x48,
    BLOBHASH = 0x49,
    BLOBBASEFEE = 0x4A, // EIP-7516

    // 0x50: Stack, Memory, Storage and Flow Operations
    POP = 0x50,
    MLOAD = 0x51,
    MSTORE = 0x52,
    MSTORE8 = 0x53,
    SLOAD = 0x54,
    SSTORE = 0x55,
    JUMP = 0x56,
    JUMPI = 0x57,
    PC = 0x58,
    MSIZE = 0x59,
    GAS = 0x5A,
    JUMPDEST = 0x5B,
    TLOAD = 0x5C, // EIP-1153
    TSTORE = 0x5D, // EIP-1153
    MCOPY = 0x5E, // EIP-5656

    // 0x60-0x7F: Push Operations
    PUSH0 = 0x5F, // EIP-3855
    PUSH1 = 0x60,
    PUSH2 = 0x61,
    PUSH3 = 0x62,
    PUSH4 = 0x63,
    PUSH5 = 0x64,
    PUSH6 = 0x65,
    PUSH7 = 0x66,
    PUSH8 = 0x67,
    PUSH9 = 0x68,
    PUSH10 = 0x69,
    PUSH11 = 0x6A,
    PUSH12 = 0x6B,
    PUSH13 = 0x6C,
    PUSH14 = 0x6D,
    PUSH15 = 0x6E,
    PUSH16 = 0x6F,
    PUSH17 = 0x70,
    PUSH18 = 0x71,
    PUSH19 = 0x72,
    PUSH20 = 0x73,
    PUSH21 = 0x74,
    PUSH22 = 0x75,
    PUSH23 = 0x76,
    PUSH24 = 0x77,
    PUSH25 = 0x78,
    PUSH26 = 0x79,
    PUSH27 = 0x7A,
    PUSH28 = 0x7B,
    PUSH29 = 0x7C,
    PUSH30 = 0x7D,
    PUSH31 = 0x7E,
    PUSH32 = 0x7F,

    // 0x80-0x8F: Duplication Operations
    DUP1 = 0x80,
    DUP2 = 0x81,
    DUP3 = 0x82,
    DUP4 = 0x83,
    DUP5 = 0x84,
    DUP6 = 0x85,
    DUP7 = 0x86,
    DUP8 = 0x87,
    DUP9 = 0x88,
    DUP10 = 0x89,
    DUP11 = 0x8A,
    DUP12 = 0x8B,
    DUP13 = 0x8C,
    DUP14 = 0x8D,
    DUP15 = 0x8E,
    DUP16 = 0x8F,

    // 0x90-0x9F: Exchange Operations
    SWAP1 = 0x90,
    SWAP2 = 0x91,
    SWAP3 = 0x92,
    SWAP4 = 0x93,
    SWAP5 = 0x94,
    SWAP6 = 0x95,
    SWAP7 = 0x96,
    SWAP8 = 0x97,
    SWAP9 = 0x98,
    SWAP10 = 0x99,
    SWAP11 = 0x9A,
    SWAP12 = 0x9B,
    SWAP13 = 0x9C,
    SWAP14 = 0x9D,
    SWAP15 = 0x9E,
    SWAP16 = 0x9F,

    // 0xA0-0xA4: Logging Operations
    LOG0 = 0xA0,
    LOG1 = 0xA1,
    LOG2 = 0xA2,
    LOG3 = 0xA3,
    LOG4 = 0xA4,

    // 0xF0-0xFF: System Operations
    CREATE = 0xF0,
    CALL = 0xF1,
    CALLCODE = 0xF2,
    RETURN = 0xF3,
    DELEGATECALL = 0xF4,
    CREATE2 = 0xF5,
    STATICCALL = 0xFA,
    REVERT = 0xFD,
    INVALID = 0xFE,
    SELFDESTRUCT = 0xFF,

    /// Convert a byte to an Opcode. Infallible.
    ///
    /// Undefined bytes return .INVALID (0xFE), which is correct EVM semantics.
    pub inline fn fromByte(byte: u8) Opcode {
        return opcodes[byte];
    }

    /// Check if a byte represents a defined opcode.
    ///
    /// Returns false for undefined bytes that map to INVALID.
    /// Returns true for 0xFE (the real INVALID opcode).
    pub inline fn isDefined(byte: u8) bool {
        return opcodes[byte] != .INVALID or byte == 0xFE;
    }

    /// Get the string name of the opcode.
    ///
    /// For PREVRANDAO, returns "PREVRANDAO" (not "DIFFICULTY").
    pub inline fn toString(self: Opcode) []const u8 {
        return @tagName(self);
    }

    /// Get the number of stack items this opcode pops.
    ///
    /// O(1) lookup from precomputed table.
    pub inline fn popCount(self: Opcode) u8 {
        return pop_count_table[@intFromEnum(self)];
    }

    /// Get the number of stack items this opcode pushes.
    ///
    /// O(1) lookup from precomputed table.
    pub inline fn pushCount(self: Opcode) u8 {
        return push_count_table[@intFromEnum(self)];
    }

    /// Get the number of immediate bytes following this opcode.
    ///
    /// Returns 1-32 for PUSH1-PUSH32, 0 for all other opcodes.
    /// O(1) lookup from precomputed table.
    pub inline fn immediateBytes(self: Opcode) u8 {
        return immediate_bytes_table[@intFromEnum(self)];
    }

    /// Check if this is a PUSH opcode (PUSH0-PUSH32).
    pub inline fn isPush(self: Opcode) bool {
        return @intFromEnum(self) >= @intFromEnum(Opcode.PUSH0) and
            @intFromEnum(self) <= @intFromEnum(Opcode.PUSH32);
    }

    /// Get the number of immediate data bytes for a PUSH opcode.
    ///
    /// Returns 0 for PUSH0 and non-PUSH opcodes, 1-32 for PUSH1-PUSH32.
    /// This is equivalent to immediateBytes() - both return the same values.
    pub inline fn pushSize(self: Opcode) usize {
        return self.immediateBytes();
    }

    /// Check if this opcode needs memory cost tracking update after execution.
    ///
    /// Memory operations (MLOAD, MSTORE, MSTORE8, MCOPY, RETURN, REVERT) need
    /// the gas accounting's internal memory size tracker updated after execution.
    /// O(1) lookup from precomputed table.
    pub inline fn needsMemoryCostUpdate(self: Opcode) bool {
        return needs_memory_update_table[@intFromEnum(self)];
    }
};

/// Lookup table mapping all 256 byte values to Opcode enum values.
///
/// Invalid/undefined bytes map to .INVALID (0xFE).
const opcodes: [256]Opcode = blk: {
    var arr = [_]Opcode{.INVALID} ** 256;

    // Automatically populate from enum definition
    for (@typeInfo(Opcode).@"enum".fields) |field| {
        const opcode = @field(Opcode, field.name);
        arr[@intFromEnum(opcode)] = opcode;
    }

    break :blk arr;
};

/// Lookup table for stack pop counts (0-7).
///
/// Built at compile time for O(1) lookup.
const pop_count_table: [256]u8 = blk: {
    @setEvalBranchQuota(5000);
    var arr = [_]u8{0} ** 256;

    for (@typeInfo(Opcode).@"enum".fields) |field| {
        const opcode: Opcode = @field(Opcode, field.name);
        const byte = @intFromEnum(opcode);
        arr[byte] = switch (opcode) {
            .STOP, .PC, .MSIZE, .GAS, .JUMPDEST, .PUSH0, .ADDRESS, .ORIGIN, .CALLER, .CALLVALUE, .CALLDATASIZE, .CODESIZE, .GASPRICE, .RETURNDATASIZE, .COINBASE, .TIMESTAMP, .NUMBER, .PREVRANDAO, .GASLIMIT, .CHAINID, .SELFBALANCE, .BASEFEE, .BLOBBASEFEE => 0,
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8, .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16, .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24, .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => 0,
            .ISZERO, .NOT, .BALANCE, .CALLDATALOAD, .EXTCODESIZE, .EXTCODEHASH, .BLOCKHASH, .POP, .MLOAD, .SLOAD, .JUMP, .TLOAD, .BLOBHASH, .SELFDESTRUCT => 1,
            .ADD, .MUL, .SUB, .DIV, .SDIV, .MOD, .SMOD, .EXP, .SIGNEXTEND, .LT, .GT, .SLT, .SGT, .EQ, .AND, .OR, .XOR, .BYTE, .SHL, .SHR, .SAR, .KECCAK256, .MSTORE, .MSTORE8, .SSTORE, .JUMPI, .TSTORE, .RETURN, .REVERT => 2,
            .ADDMOD, .MULMOD, .CALLDATACOPY, .CODECOPY, .RETURNDATACOPY, .MCOPY, .CREATE => 3,
            .EXTCODECOPY, .CREATE2 => 4,
            .CALL, .CALLCODE => 7,
            .DELEGATECALL, .STATICCALL => 6,
            .LOG0 => 2,
            .LOG1 => 3,
            .LOG2 => 4,
            .LOG3 => 5,
            .LOG4 => 6,
            .DUP1, .DUP2, .DUP3, .DUP4, .DUP5, .DUP6, .DUP7, .DUP8, .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16 => blk2: {
                const n = @intFromEnum(opcode) - @intFromEnum(Opcode.DUP1) + 1;
                break :blk2 n;
            },
            .SWAP1, .SWAP2, .SWAP3, .SWAP4, .SWAP5, .SWAP6, .SWAP7, .SWAP8, .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16 => blk2: {
                const n = @intFromEnum(opcode) - @intFromEnum(Opcode.SWAP1) + 1;
                break :blk2 n + 1;
            },
            .INVALID => 0,
        };
    }

    break :blk arr;
};

/// Lookup table for stack push counts (0-17).
///
/// Built at compile time for O(1) lookup.
const push_count_table: [256]u8 = blk: {
    @setEvalBranchQuota(5000);
    var arr = [_]u8{0} ** 256;

    for (@typeInfo(Opcode).@"enum".fields) |field| {
        const opcode: Opcode = @field(Opcode, field.name);
        const byte = @intFromEnum(opcode);
        arr[byte] = switch (opcode) {
            .STOP, .RETURN, .REVERT, .INVALID, .SELFDESTRUCT, .JUMP, .JUMPI, .JUMPDEST, .POP, .MSTORE, .MSTORE8, .SSTORE, .CALLDATACOPY, .CODECOPY, .EXTCODECOPY, .RETURNDATACOPY, .TSTORE, .MCOPY, .LOG0, .LOG1, .LOG2, .LOG3, .LOG4 => 0,
            .ADD, .MUL, .SUB, .DIV, .SDIV, .MOD, .SMOD, .ADDMOD, .MULMOD, .EXP, .SIGNEXTEND, .LT, .GT, .SLT, .SGT, .EQ, .ISZERO, .AND, .OR, .XOR, .NOT, .BYTE, .SHL, .SHR, .SAR, .KECCAK256, .ADDRESS, .BALANCE, .ORIGIN, .CALLER, .CALLVALUE, .CALLDATALOAD, .CALLDATASIZE, .CODESIZE, .GASPRICE, .EXTCODESIZE, .RETURNDATASIZE, .EXTCODEHASH, .BLOCKHASH, .COINBASE, .TIMESTAMP, .NUMBER, .PREVRANDAO, .GASLIMIT, .CHAINID, .SELFBALANCE, .BASEFEE, .BLOBHASH, .BLOBBASEFEE, .MLOAD, .SLOAD, .PC, .MSIZE, .GAS, .PUSH0, .TLOAD, .CREATE, .CREATE2, .CALL, .CALLCODE, .DELEGATECALL, .STATICCALL => 1,
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8, .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16, .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24, .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => 1,
            .DUP1, .DUP2, .DUP3, .DUP4, .DUP5, .DUP6, .DUP7, .DUP8, .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16 => blk2: {
                const n = @intFromEnum(opcode) - @intFromEnum(Opcode.DUP1) + 1;
                break :blk2 n + 1;
            },
            .SWAP1, .SWAP2, .SWAP3, .SWAP4, .SWAP5, .SWAP6, .SWAP7, .SWAP8, .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16 => blk2: {
                const n = @intFromEnum(opcode) - @intFromEnum(Opcode.SWAP1) + 1;
                break :blk2 n + 1;
            },
        };
    }

    break :blk arr;
};

/// Lookup table for immediate byte counts (0-32).
///
/// Built at compile time for O(1) lookup.
const immediate_bytes_table: [256]u8 = blk: {
    @setEvalBranchQuota(5000);
    var arr = [_]u8{0} ** 256;

    for (@typeInfo(Opcode).@"enum".fields) |field| {
        const opcode: Opcode = @field(Opcode, field.name);
        const byte = @intFromEnum(opcode);
        arr[byte] = switch (opcode) {
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8, .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16, .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24, .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => blk2: {
                const n = @intFromEnum(opcode) - @intFromEnum(Opcode.PUSH1) + 1;
                break :blk2 n;
            },
            else => 0,
        };
    }

    break :blk arr;
};

/// Lookup table for opcodes that need memory cost tracking updates.
///
/// Built at compile time for O(1) lookup.
const needs_memory_update_table: [256]bool = blk: {
    var arr = [_]bool{false} ** 256;

    // Only these memory-touching opcodes need updates.
    arr[@intFromEnum(Opcode.MLOAD)] = true;
    arr[@intFromEnum(Opcode.MSTORE)] = true;
    arr[@intFromEnum(Opcode.MSTORE8)] = true;
    arr[@intFromEnum(Opcode.MCOPY)] = true;
    arr[@intFromEnum(Opcode.RETURN)] = true;
    arr[@intFromEnum(Opcode.REVERT)] = true;

    break :blk arr;
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "fromByte - valid opcodes" {
    const test_cases = [_]struct {
        byte: u8,
        expected: Opcode,
    }{
        .{ .byte = 0x00, .expected = .STOP },
        .{ .byte = 0x01, .expected = .ADD },
        .{ .byte = 0x60, .expected = .PUSH1 },
        .{ .byte = 0x7F, .expected = .PUSH32 },
        .{ .byte = 0x80, .expected = .DUP1 },
        .{ .byte = 0x90, .expected = .SWAP1 },
        .{ .byte = 0xFF, .expected = .SELFDESTRUCT },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, Opcode.fromByte(tc.byte));
    }
}

test "fromByte - invalid opcodes" {
    const invalid_bytes = [_]u8{
        0x0C, // Gap in 0x0C-0x0F
        0x1E, // Gap after SAR
        0x21, // Gap after KECCAK256
        0x4B, // Gap after BLOBBASEFEE
        0xA5, // Gap after LOG4
        0xF6, // Gap in system ops
    };

    for (invalid_bytes) |byte| {
        // Opcode default to invalid, use isDefined to distinguish between truly undefined and INVALID.
        try expectEqual(.INVALID, Opcode.fromByte(byte));
        try expect(!Opcode.isDefined(byte));
    }
}

test "toString" {
    const test_cases = [_]struct {
        opcode: Opcode,
        expected: []const u8,
    }{
        .{ .opcode = .STOP, .expected = "STOP" },
        .{ .opcode = .ADD, .expected = "ADD" },
        .{ .opcode = .PUSH1, .expected = "PUSH1" },
        .{ .opcode = .PREVRANDAO, .expected = "PREVRANDAO" },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, tc.opcode.toString());
    }
}

test "popCount" {
    const test_cases = [_]struct {
        opcode: Opcode,
        expected: u8,
    }{
        .{ .opcode = .STOP, .expected = 0 },
        .{ .opcode = .PUSH1, .expected = 0 },
        .{ .opcode = .PUSH32, .expected = 0 },
        .{ .opcode = .POP, .expected = 1 },
        .{ .opcode = .ISZERO, .expected = 1 },
        .{ .opcode = .ADD, .expected = 2 },
        .{ .opcode = .MUL, .expected = 2 },
        .{ .opcode = .ADDMOD, .expected = 3 },
        .{ .opcode = .DUP1, .expected = 1 },
        .{ .opcode = .DUP2, .expected = 2 },
        .{ .opcode = .SWAP1, .expected = 2 },
        .{ .opcode = .SWAP2, .expected = 3 },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, tc.opcode.popCount());
    }
}

test "pushCount" {
    const test_cases = [_]struct {
        opcode: Opcode,
        expected: u8,
    }{
        .{ .opcode = .STOP, .expected = 0 },
        .{ .opcode = .POP, .expected = 0 },
        .{ .opcode = .ADD, .expected = 1 },
        .{ .opcode = .PUSH1, .expected = 1 },
        .{ .opcode = .PUSH32, .expected = 1 },
        .{ .opcode = .DUP1, .expected = 2 }, // n+1
        .{ .opcode = .DUP2, .expected = 3 }, // n+1
        .{ .opcode = .SWAP1, .expected = 2 }, // n+1
        .{ .opcode = .SWAP2, .expected = 3 }, // n+1
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, tc.opcode.pushCount());
    }
}

test "immediateBytes" {
    const test_cases = [_]struct {
        opcode: Opcode,
        expected: u8,
    }{
        .{ .opcode = .ADD, .expected = 0 },
        .{ .opcode = .STOP, .expected = 0 },
        .{ .opcode = .PUSH1, .expected = 1 },
        .{ .opcode = .PUSH2, .expected = 2 },
        .{ .opcode = .PUSH16, .expected = 16 },
        .{ .opcode = .PUSH32, .expected = 32 },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, tc.opcode.immediateBytes());
    }
}

test "isPush" {
    // PUSH opcodes
    try expect(Opcode.PUSH0.isPush());
    try expect(Opcode.PUSH1.isPush());
    try expect(Opcode.PUSH2.isPush());
    try expect(Opcode.PUSH16.isPush());
    try expect(Opcode.PUSH32.isPush());

    // Non-PUSH opcodes
    try expect(!Opcode.ADD.isPush());
    try expect(!Opcode.STOP.isPush());
    try expect(!Opcode.JUMP.isPush());
    try expect(!Opcode.JUMPDEST.isPush());
    try expect(!Opcode.DUP1.isPush());
}

test "pushSize" {
    const test_cases = [_]struct {
        opcode: Opcode,
        expected: usize,
    }{
        .{ .opcode = .PUSH0, .expected = 0 },
        .{ .opcode = .PUSH1, .expected = 1 },
        .{ .opcode = .PUSH2, .expected = 2 },
        .{ .opcode = .PUSH16, .expected = 16 },
        .{ .opcode = .PUSH32, .expected = 32 },
        // Non-PUSH opcodes should return 0
        .{ .opcode = .ADD, .expected = 0 },
        .{ .opcode = .STOP, .expected = 0 },
        .{ .opcode = .JUMP, .expected = 0 },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, tc.opcode.pushSize());
    }
}
