//! EVM Opcode definitions and metadata.
//!
//! Reference: https://www.evm.codes/

const std = @import("std");
const Spec = @import("../hardfork.zig").Spec;
const Costs = @import("gas/costs.zig").Costs;

/// EVM Opcode.
///
/// Each opcode is mapped to its exact byte value as defined in the EVM spec.
/// Only valid opcodes are defined; invalid bytes will return an error from fromByte().
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

    /// Convert a byte to an Opcode.
    pub fn fromByte(byte: u8) Error!Opcode {
        return std.enums.fromInt(Opcode, byte) orelse error.InvalidOpcode;
    }

    /// Get the string name of the opcode.
    ///
    /// For PREVRANDAO, returns "PREVRANDAO" (not "DIFFICULTY").
    pub inline fn toString(self: Opcode) []const u8 {
        return @tagName(self);
    }

    /// Get the number of stack items this opcode pops.
    pub inline fn popCount(self: Opcode) u8 {
        return switch (self) {
            // 0 inputs
            .STOP, .PC, .MSIZE, .GAS, .JUMPDEST, .PUSH0, .ADDRESS, .ORIGIN, .CALLER, .CALLVALUE, .CALLDATASIZE, .CODESIZE, .GASPRICE, .RETURNDATASIZE, .COINBASE, .TIMESTAMP, .NUMBER, .PREVRANDAO, .GASLIMIT, .CHAINID, .SELFBALANCE, .BASEFEE, .BLOBBASEFEE => 0,

            // PUSH1-PUSH32: 0 inputs
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8, .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16, .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24, .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => 0,

            // 1 input
            .ISZERO, .NOT, .BALANCE, .CALLDATALOAD, .EXTCODESIZE, .EXTCODEHASH, .BLOCKHASH, .POP, .MLOAD, .SLOAD, .JUMP, .TLOAD, .BLOBHASH, .SELFDESTRUCT => 1,

            // 2 inputs
            .ADD, .MUL, .SUB, .DIV, .SDIV, .MOD, .SMOD, .EXP, .SIGNEXTEND, .LT, .GT, .SLT, .SGT, .EQ, .AND, .OR, .XOR, .BYTE, .SHL, .SHR, .SAR, .KECCAK256, .MSTORE, .MSTORE8, .SSTORE, .JUMPI, .TSTORE, .RETURN, .REVERT => 2,

            // 3 inputs
            .ADDMOD, .MULMOD, .CALLDATACOPY, .CODECOPY, .RETURNDATACOPY, .MCOPY, .CREATE => 3,

            // 4 inputs
            .EXTCODECOPY, .CREATE2 => 4,

            // 6 inputs
            .CALL, .CALLCODE => 7, // Actually 7 inputs

            // 6 inputs
            .DELEGATECALL, .STATICCALL => 6,

            // LOG0-LOG4: 2 + topic count
            .LOG0 => 2,
            .LOG1 => 3,
            .LOG2 => 4,
            .LOG3 => 5,
            .LOG4 => 6,

            // DUP1-DUP16: n inputs (to read from)
            .DUP1, .DUP2, .DUP3, .DUP4, .DUP5, .DUP6, .DUP7, .DUP8, .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16 => {
                const n = @intFromEnum(self) - @intFromEnum(Opcode.DUP1) + 1;
                return n;
            },

            // SWAP1-SWAP16: n+1 inputs
            .SWAP1, .SWAP2, .SWAP3, .SWAP4, .SWAP5, .SWAP6, .SWAP7, .SWAP8, .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16 => {
                const n = @intFromEnum(self) - @intFromEnum(Opcode.SWAP1) + 1;
                return n + 1;
            },

            .INVALID => 0,
        };
    }

    /// Get the number of stack items this opcode pushes.
    pub inline fn pushCount(self: Opcode) u8 {
        return switch (self) {
            // 0 outputs (halts or doesn't produce a value)
            .STOP, .RETURN, .REVERT, .INVALID, .SELFDESTRUCT, .JUMP, .JUMPI, .JUMPDEST, .POP, .MSTORE, .MSTORE8, .SSTORE, .CALLDATACOPY, .CODECOPY, .EXTCODECOPY, .RETURNDATACOPY, .TSTORE, .MCOPY, .LOG0, .LOG1, .LOG2, .LOG3, .LOG4 => 0,

            // 1 output (most instructions)
            .ADD, .MUL, .SUB, .DIV, .SDIV, .MOD, .SMOD, .ADDMOD, .MULMOD, .EXP, .SIGNEXTEND, .LT, .GT, .SLT, .SGT, .EQ, .ISZERO, .AND, .OR, .XOR, .NOT, .BYTE, .SHL, .SHR, .SAR, .KECCAK256, .ADDRESS, .BALANCE, .ORIGIN, .CALLER, .CALLVALUE, .CALLDATALOAD, .CALLDATASIZE, .CODESIZE, .GASPRICE, .EXTCODESIZE, .RETURNDATASIZE, .EXTCODEHASH, .BLOCKHASH, .COINBASE, .TIMESTAMP, .NUMBER, .PREVRANDAO, .GASLIMIT, .CHAINID, .SELFBALANCE, .BASEFEE, .BLOBHASH, .BLOBBASEFEE, .MLOAD, .SLOAD, .PC, .MSIZE, .GAS, .PUSH0, .TLOAD, .CREATE, .CREATE2, .CALL, .CALLCODE, .DELEGATECALL, .STATICCALL => 1,

            // PUSH1-PUSH32: 1 output
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8, .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16, .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24, .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => 1,

            // DUP1-DUP16: n+1 outputs (original n + duplicate)
            .DUP1, .DUP2, .DUP3, .DUP4, .DUP5, .DUP6, .DUP7, .DUP8, .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16 => {
                const n = @intFromEnum(self) - @intFromEnum(Opcode.DUP1) + 1;
                return n + 1;
            },

            // SWAP1-SWAP16: n+1 outputs (same as inputs)
            .SWAP1, .SWAP2, .SWAP3, .SWAP4, .SWAP5, .SWAP6, .SWAP7, .SWAP8, .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16 => {
                const n = @intFromEnum(self) - @intFromEnum(Opcode.SWAP1) + 1;
                return n + 1;
            },
        };
    }

    /// Get the number of immediate bytes following this opcode.
    ///
    /// Returns 1-32 for PUSH1-PUSH32, 0 for all other opcodes.
    pub inline fn immediateBytes(self: Opcode) u8 {
        return switch (self) {
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8, .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16, .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24, .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => {
                // Use arithmetic: PUSH1 = 1 byte, PUSH2 = 2 bytes, etc.
                return @intFromEnum(self) - @intFromEnum(Opcode.PUSH1) + 1;
            },
            else => 0,
        };
    }

    /// Check if this is a PUSH opcode (PUSH0-PUSH32).
    pub inline fn isPush(self: Opcode) bool {
        return @intFromEnum(self) >= @intFromEnum(Opcode.PUSH0) and
            @intFromEnum(self) <= @intFromEnum(Opcode.PUSH32);
    }

    /// Get the number of immediate data bytes for a PUSH opcode.
    ///
    /// Returns 0 for PUSH0 and non-PUSH opcodes, 1-32 for PUSH1-PUSH32.
    pub inline fn pushSize(self: Opcode) usize {
        if (!self.isPush()) return 0;
        if (self == .PUSH0) return 0;
        // PUSH1 = 1 byte, PUSH2 = 2 bytes, ..., PUSH32 = 32 bytes
        return @intFromEnum(self) - @intFromEnum(Opcode.PUSH0);
    }

    /// Check if this is a control flow opcode that manages PC directly.
    ///
    /// These opcodes either halt execution or modify PC explicitly,
    /// so the interpreter should not auto-increment PC after executing them.
    pub inline fn isControlFlow(self: Opcode) bool {
        return switch (self) {
            .STOP, .JUMP, .JUMPI, .RETURN, .REVERT, .INVALID, .SELFDESTRUCT => true,
            else => false,
        };
    }

    /// Get the base gas cost for this opcode.
    ///
    /// Some opcodes (like EXP, SLOAD, CALL) have additional dynamic costs
    /// that must be computed and charged separately during execution.
    pub fn baseCost(self: Opcode, spec: Spec) u64 {
        return switch (self) {
            // ZERO tier (0 gas)
            .STOP, .RETURN, .REVERT => Costs.ZERO,

            // BASE tier (2 gas)
            .ADDRESS, .ORIGIN, .CALLER, .CALLVALUE, .CALLDATASIZE, .CODESIZE, .GASPRICE, .RETURNDATASIZE, .COINBASE, .TIMESTAMP, .NUMBER, .PREVRANDAO, .GASLIMIT, .CHAINID, .BASEFEE, .BLOBBASEFEE, .PC, .MSIZE, .GAS, .POP => Costs.BASE,

            // VERYLOW tier (3 gas)
            .ADD, .SUB, .NOT, .LT, .GT, .SLT, .SGT, .EQ, .ISZERO, .AND, .OR, .XOR, .BYTE, .CALLDATALOAD, .MLOAD, .MSTORE, .MSTORE8, .PUSH0 => Costs.VERYLOW,

            // PUSH1-PUSH32: VERYLOW (3 gas)
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8, .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16, .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24, .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => Costs.PUSH,

            // DUP1-DUP16: VERYLOW (3 gas)
            .DUP1, .DUP2, .DUP3, .DUP4, .DUP5, .DUP6, .DUP7, .DUP8, .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16 => Costs.DUP,

            // SWAP1-SWAP16: VERYLOW (3 gas)
            .SWAP1, .SWAP2, .SWAP3, .SWAP4, .SWAP5, .SWAP6, .SWAP7, .SWAP8, .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16 => Costs.SWAP,

            // LOW tier (5 gas)
            .MUL, .DIV, .SDIV, .MOD, .SMOD, .SIGNEXTEND, .SELFBALANCE => Costs.LOW,

            // MID tier (8 gas)
            .ADDMOD, .MULMOD, .JUMP => Costs.MID,

            // HIGH tier (10 gas)
            .JUMPI => Costs.HIGH,

            // Special: EXP (base cost, dynamic cost charged separately)
            .EXP => Costs.EXP_BASE,

            // Shift operations (EIP-145, Constantinople+)
            .SHL, .SHR, .SAR => Costs.VERYLOW,

            // JUMPDEST
            .JUMPDEST => Costs.JUMPDEST,

            // Hashing
            .KECCAK256 => Costs.KECCAK256_BASE, // + per-word cost

            // Memory operations with expansion costs
            .CALLDATACOPY, .CODECOPY, .RETURNDATACOPY => Costs.VERYLOW, // + expansion
            .EXTCODECOPY => if (spec.fork.isAtLeast(.BERLIN)) Costs.EXTCODECOPY_BASE else 700,
            .MCOPY => Costs.VERYLOW, // + per-word, Cancun+

            // Environmental info with cold/warm costs
            .BALANCE => if (spec.fork.isAtLeast(.BERLIN))
                Costs.BALANCE // Warm, cold charged separately
            else if (spec.fork.isAtLeast(.TANGERINE))
                400
            else
                20,

            .EXTCODESIZE => if (spec.fork.isAtLeast(.BERLIN))
                Costs.EXTCODESIZE // Warm
            else if (spec.fork.isAtLeast(.TANGERINE))
                700
            else
                20,

            .EXTCODEHASH => if (spec.fork.isAtLeast(.BERLIN))
                Costs.EXTCODEHASH // Warm, Istanbul+
            else
                400,

            .BLOCKHASH => Costs.BLOCKHASH,

            // Storage operations (dynamic costs)
            .SLOAD => if (spec.fork.isAtLeast(.BERLIN))
                spec.warm_storage_read_cost // EIP-2929
            else if (spec.fork.isAtLeast(.TANGERINE))
                200
            else
                50,

            .SSTORE => Costs.SSTORE_UNCHANGED, // Base cost, actual cost computed dynamically

            // Transient storage (EIP-1153, Cancun+)
            .TLOAD, .TSTORE => Costs.TLOAD,

            // Blob operations (EIP-4844, Cancun+)
            .BLOBHASH => Costs.BLOBHASH,

            // Logging operations
            .LOG0 => Costs.LOG_BASE,
            .LOG1 => Costs.LOG_BASE + Costs.LOG_TOPIC,
            .LOG2 => Costs.LOG_BASE + 2 * Costs.LOG_TOPIC,
            .LOG3 => Costs.LOG_BASE + 3 * Costs.LOG_TOPIC,
            .LOG4 => Costs.LOG_BASE + 4 * Costs.LOG_TOPIC,

            // System operations (complex dynamic costs)
            .CREATE => Costs.CREATE_BASE,
            .CREATE2 => Costs.CREATE2_BASE,
            .CALL, .CALLCODE => if (spec.fork.isAtLeast(.BERLIN))
                Costs.CALL_BASE // Warm
            else if (spec.fork.isAtLeast(.TANGERINE))
                700
            else
                40,
            .DELEGATECALL, .STATICCALL => if (spec.fork.isAtLeast(.BERLIN))
                Costs.DELEGATECALL_BASE // Warm
            else
                700,

            .SELFDESTRUCT => if (spec.fork.isAtLeast(.TANGERINE))
                Costs.SELFDESTRUCT_BASE
            else
                0,

            .INVALID => 0, // Consumes all gas, but base is 0
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Opcode: fromByte - valid opcodes" {
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
        try expectEqual(tc.expected, try Opcode.fromByte(tc.byte));
    }
}

test "Opcode: fromByte - invalid opcodes" {
    const invalid_bytes = [_]u8{
        0x0C, // Gap in 0x0C-0x0F
        0x1E, // Gap after SAR
        0x21, // Gap after KECCAK256
        0x4B, // Gap after BLOBBASEFEE
        0xA5, // Gap after LOG4
        0xF6, // Gap in system ops
    };

    for (invalid_bytes) |byte| {
        try expectError(error.InvalidOpcode, Opcode.fromByte(byte));
    }
}

test "Opcode: toString" {
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

test "Opcode: popCount" {
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

test "Opcode: pushCount" {
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

test "Opcode: immediateBytes" {
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

test "Opcode: isControlFlow" {
    try expect(Opcode.STOP.isControlFlow());
    try expect(Opcode.JUMP.isControlFlow());
    try expect(Opcode.JUMPI.isControlFlow());
    try expect(Opcode.RETURN.isControlFlow());
    try expect(Opcode.REVERT.isControlFlow());
    try expect(Opcode.INVALID.isControlFlow());
    try expect(Opcode.SELFDESTRUCT.isControlFlow());

    try expect(!Opcode.ADD.isControlFlow());
    try expect(!Opcode.PUSH1.isControlFlow());
    try expect(!Opcode.JUMPDEST.isControlFlow());
}

test "Opcode: baseCost" {
    const spec_frontier = Spec.forFork(.FRONTIER);
    const spec_berlin = Spec.forFork(.BERLIN);

    // Zero tier
    try expectEqual(0, Opcode.STOP.baseCost(spec_frontier));
    try expectEqual(0, Opcode.RETURN.baseCost(spec_frontier));

    // Base tier
    try expectEqual(2, Opcode.ADDRESS.baseCost(spec_frontier));
    try expectEqual(2, Opcode.POP.baseCost(spec_frontier));

    // Verylow tier
    try expectEqual(3, Opcode.ADD.baseCost(spec_frontier));
    try expectEqual(3, Opcode.PUSH1.baseCost(spec_frontier));
    try expectEqual(3, Opcode.PUSH32.baseCost(spec_frontier));

    // Low tier
    try expectEqual(5, Opcode.MUL.baseCost(spec_frontier));
    try expectEqual(5, Opcode.DIV.baseCost(spec_frontier));

    // Mid tier
    try expectEqual(8, Opcode.ADDMOD.baseCost(spec_frontier));

    // High tier
    try expectEqual(10, Opcode.JUMPI.baseCost(spec_frontier));

    // EXP base
    try expectEqual(10, Opcode.EXP.baseCost(spec_frontier));

    // Fork-specific: BALANCE changed in Tangerine and Berlin
    try expectEqual(20, Opcode.BALANCE.baseCost(spec_frontier));
    try expectEqual(100, Opcode.BALANCE.baseCost(spec_berlin)); // Warm cost

    // Fork-specific: SLOAD changed in Tangerine and Berlin
    try expectEqual(50, Opcode.SLOAD.baseCost(spec_frontier));
    try expectEqual(100, Opcode.SLOAD.baseCost(spec_berlin)); // Warm cost
}

test "Opcode: isPush" {
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

test "Opcode: pushSize" {
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
