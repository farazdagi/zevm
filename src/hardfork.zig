//! Hardfork specifications.
//!
//! A Spec is the single source of truth on static/fixed configuration.
//! Fixed/base opcode costs and opcode availability are defined for each
//! fork via `updateCosts` and `updateHandlers` methods respectively.
//!
//! For dynamic costs see `DynamicGasCosts`.
const std = @import("std");

const FixedGasCosts = @import("gas/FixedGasCosts.zig");
const Opcode = @import("interpreter/opcode.zig").Opcode;
const InstructionTable = @import("interpreter/InstructionTable.zig");
const handlers = @import("interpreter/handlers/mod.zig");
const DynamicGasCosts = @import("gas/DynamicGasCosts.zig");

/// Ethereum hard fork identifier.
///
/// A fork determines which rules, gas costs, and opcodes are active.
///
/// Ordered chronologically from oldest to newest.
/// See: https://ethereum.org/ethereum-forks/ for timeline of Ethereum forks.
pub const Hardfork = enum(u8) {
    FRONTIER = 0,
    FRONTIER_THAWING = 1,
    HOMESTEAD = 2,
    DAO_FORK = 3,
    TANGERINE = 4,
    SPURIOUS_DRAGON = 5,
    BYZANTIUM = 6,
    CONSTANTINOPLE = 7,
    PETERSBURG = 8,
    ISTANBUL = 9,
    MUIR_GLACIER = 10,
    BERLIN = 11,
    LONDON = 12,
    ARROW_GLACIER = 13,
    GRAY_GLACIER = 14,
    MERGE = 15, // Paris
    SHANGHAI = 16,
    CANCUN = 17,
    PRAGUE = 18,
    OSAKA = 19, // Q4, 2025

    /// Latest implemented fork
    pub const LATEST = Hardfork.PRAGUE;

    /// Check if this fork is at least the specified fork
    pub fn isAtLeast(self: Hardfork, other: Hardfork) bool {
        return @intFromEnum(self) >= @intFromEnum(other);
    }

    /// Check if this fork is before the specified fork
    pub fn isBefore(self: Hardfork, other: Hardfork) bool {
        return @intFromEnum(self) < @intFromEnum(other);
    }

    /// Get fork name for display
    pub fn name(self: Hardfork) []const u8 {
        return switch (self) {
            .FRONTIER => "Frontier",
            .FRONTIER_THAWING => "Frontier Thawing",
            .HOMESTEAD => "Homestead",
            .DAO_FORK => "DAO Fork",
            .TANGERINE => "Tangerine Whistle",
            .SPURIOUS_DRAGON => "Spurious Dragon",
            .BYZANTIUM => "Byzantium",
            .CONSTANTINOPLE => "Constantinople",
            .PETERSBURG => "Petersburg",
            .ISTANBUL => "Istanbul",
            .MUIR_GLACIER => "Muir Glacier",
            .BERLIN => "Berlin",
            .LONDON => "London",
            .ARROW_GLACIER => "Arrow Glacier",
            .GRAY_GLACIER => "Gray Glacier",
            .MERGE => "Paris/Merge",
            .SHANGHAI => "Shanghai",
            .CANCUN => "Cancun",
            .PRAGUE => "Prague",
            .OSAKA => "Osaka",
        };
    }
};

/// Hard fork specification with all fork-specific rules.
///
/// Includes configuration for: gas costs and refund rules, opcode availability,
/// limits and constraints, precompile addresses etc.
pub const Spec = struct {
    /// Fork
    fork: Hardfork,

    /// Base fork this fork is built upon (null only for FRONTIER)
    base_fork: ?Hardfork,

    /// Network chain identifier (EIP-155).
    ///
    /// Examples: 1 (Ethereum mainnet), 10 (Optimism), 11155111 (Sepolia)
    ///
    /// NOTE: For multi-chain support, this will be derived from Hardfork enum
    /// when chain-specific fork variants are added (e.g., OPTIMISM_CANYON).
    chain_id: u64,

    /// Optional function to update BASE gas costs for this fork.
    ///
    /// If null, this fork introduces no gas cost changes from its base.
    updateCosts: ?*const fn (*[256]u64, Spec) void,

    /// Optional function to update instruction handlers for this fork.
    ///
    /// If null, this fork introduces no handler changes from its base.
    /// This populates the instruction table with opcode handlers appropriate
    /// for the fork's features and enabled opcodes.
    updateHandlers: ?*const fn (*InstructionTable) void,

    /// Maximum operand stack depth.
    stack_limit: usize = 1024,

    /// Maximum call depth (nested CALL/CREATE operations).
    call_depth_limit: usize = 1024,

    /// Number of block hashes accessible via BLOCKHASH (pre-Prague).
    block_hash_history: u64 = 256,

    /// EIP-3529: Reduction in refunds
    /// Pre-London: 2 (50%), Post-London: 5 (20%)
    max_refund_quotient: u64,

    /// SSTORE refund when clearing storage
    /// Pre-EIP-3529: 15000, Post-EIP-3529: 4800
    sstore_clears_schedule: u64,

    /// SELFDESTRUCT refund (removed in EIP-3529)
    /// Pre-EIP-3529: 24000, Post-EIP-3529: 0
    selfdestruct_refund: u64,

    /// EIP-2929: Gas cost increases for state access opcodes
    /// Cost of cold SLOAD
    cold_sload_cost: u64,

    /// Cost of cold account access (CALL, BALANCE, EXTCODESIZE, etc.)
    cold_account_access_cost: u64,

    /// Cost of warm storage read
    warm_storage_read_cost: u64,

    /// EIP-2200: Base storage read cost used in SSTORE gas formulas (`SLOAD_GAS` constant).
    ///
    /// Pre-Berlin: Tracks `cold_sload_cost` (the only SLOAD cost at the time).
    /// Berlin+: Uses `warm_storage_read_cost` (SSTORE assumes slot is already accessed).
    sload_gas: u64 = 50,

    /// EIP-3860: Limit and meter initcode
    /// Maximum initcode size (null = no limit)
    max_initcode_size: ?usize,

    /// Cost per word of initcode
    initcode_word_cost: u64,

    /// Cost per word (32 bytes) for KECCAK256 hashing.
    keccak256_word_cost: u64 = 6,

    /// Cost per word (32 bytes) for memory copy operations.
    /// Used by CALLDATACOPY, CODECOPY, EXTCODECOPY, RETURNDATACOPY, MCOPY.
    copy_word_cost: u64 = 3,

    /// Gas cost for SSTORE when setting storage (zero -> non-zero).
    sstore_set_gas: u64 = 20000,

    /// Gas cost for SSTORE when resetting storage (non-zero -> different).
    sstore_reset_gas: u64 = 5000,

    /// Log costs (constant across all forks).
    log_base_cost: u64 = 375,
    log_topic_cost: u64 = 375,
    log_data_cost: u64 = 8,

    /// Cost per zero byte in calldata.
    calldata_zero_cost: u64 = 4,

    /// CALL costs.
    call_value_transfer_cost: u64 = 9000,
    call_new_account_cost: u64 = 25000,
    call_stipend: u64 = 2300,

    /// EIP-170: Contract code size limit
    /// Maximum contract code size (0x6000 = 2**14 + 2**13 = 24576 bytes = 24KB)
    max_code_size: usize,

    /// EIP-3855: PUSH0 instruction
    /// Opcode availability
    has_push0: bool,

    /// EIP-3198: BASEFEE opcode
    has_basefee: bool,

    /// EIP-4399: PREVRANDAO opcode (replaces DIFFICULTY post-Merge)
    has_prevrandao: bool,

    /// SELFDESTRUCT still available (may be removed in future)
    has_selfdestruct: bool,

    /// EIP-1153: Transient storage (TLOAD, TSTORE)
    has_tstore: bool,

    /// EIP-5656: MCOPY instruction
    has_mcopy: bool,

    /// EIP-1559: Base fee in block
    /// Block validation
    has_base_fee: bool,

    /// EIP-4844: Blob opcodes (BLOBHASH, BLOBBASEFEE)
    has_blob_opcodes: bool,

    /// EIP-4844: Blob gas in block
    has_blob_gas: bool,

    /// EIP-4844 & EIP-7691: Blob parameters
    /// Target number of blobs per block (3 for Cancun, 6 for Prague)
    target_blobs_per_block: u8,

    /// Maximum number of blobs per block (6 for Cancun, 9 for Prague)
    max_blobs_per_block: u8,

    /// EIP-7702: Set EOA account code for one transaction
    // Prague additions
    has_eip7702: bool,

    /// EIP-2537: BLS12-381 curve precompiles
    has_bls_precompiles: bool,

    /// EIP-2935: Historical block hashes in state (8192 blocks)
    has_historical_block_hashes: bool,

    /// Get the spec for a specific fork
    pub fn forFork(fork: Hardfork) Spec {
        return switch (fork) {
            .FRONTIER => FRONTIER,
            .FRONTIER_THAWING => FRONTIER_THAWING,
            .HOMESTEAD => HOMESTEAD,
            .DAO_FORK => DAO_FORK,
            .TANGERINE => TANGERINE,
            .SPURIOUS_DRAGON => SPURIOUS_DRAGON,
            .BYZANTIUM => BYZANTIUM,
            .CONSTANTINOPLE => CONSTANTINOPLE,
            .PETERSBURG => PETERSBURG,
            .ISTANBUL => ISTANBUL,
            .MUIR_GLACIER => MUIR_GLACIER,
            .BERLIN => BERLIN,
            .LONDON => LONDON,
            .ARROW_GLACIER => ARROW_GLACIER,
            .GRAY_GLACIER => GRAY_GLACIER,
            .MERGE => MERGE,
            .SHANGHAI => SHANGHAI,
            .CANCUN => CANCUN,
            .PRAGUE => PRAGUE,
            .OSAKA => PRAGUE, // Future: use latest implemented
        };
    }

    /// Get base gas costs for all defined opcodes.
    pub fn gasCosts(self: Spec) FixedGasCosts {
        return FixedGasCosts.forFork(self.fork);
    }

    /// Get base gas cost for a given opcode.
    pub inline fn gasCost(self: Spec, opcode_byte: u8) u64 {
        return FixedGasCosts.forFork(self.fork).costs[opcode_byte];
    }

    /// Get instruction jump table for all defined opcodes.
    ///
    /// Returns pointer to static comptime-generated table, avoiding copy.
    pub fn instructionTable(self: Spec) *const InstructionTable {
        return InstructionTable.forFork(self.fork);
    }

    /// Check if a specific EIP is active in this fork
    pub fn hasEIP(self: Spec, comptime eip: u16) bool {
        return switch (eip) {
            // EIP-3529: Reduction in refunds
            3529 => self.max_refund_quotient == 5,
            // EIP-3855: PUSH0 instruction
            3855 => self.has_push0,
            // EIP-3198: BASEFEE opcode
            3198 => self.has_basefee,
            // EIP-4399: PREVRANDAO opcode
            4399 => self.has_prevrandao,
            // EIP-1153: Transient storage
            1153 => self.has_tstore,
            // EIP-4844: Shard blob transactions
            4844 => self.has_blob_opcodes,
            // EIP-5656: MCOPY instruction
            5656 => self.has_mcopy,
            // EIP-2929: Gas cost increases
            2929 => self.cold_sload_cost == 2100,
            // EIP-3860: Limit and meter initcode
            3860 => self.max_initcode_size != null,
            // EIP-170: Contract code size limit
            170 => self.max_code_size == 24576,
            // EIP-1559: Fee market
            1559 => self.has_base_fee,
            else => false,
        };
    }
};

/// Build a new Spec based on a previous fork with specified field overrides.
///
/// This helper reduces repetition when defining fork specs by allowing you to
/// specify only the fields that change from the base fork.
///
/// Example:
/// ```
/// pub const LONDON = forkSpec(.LONDON, BERLIN, .{
///     .max_refund_quotient = 5,      // EIP-3529
///     .has_basefee = true,           // EIP-3198
/// });
/// ```
fn forkSpec(
    comptime fork: Hardfork,
    comptime base: Spec,
    comptime changes: anytype,
) Spec {
    var result = base;
    result.fork = fork;
    result.base_fork = base.fork;

    // Apply all field overrides from the changes struct
    inline for (std.meta.fields(@TypeOf(changes))) |field| {
        @field(result, field.name) = @field(changes, field.name);
    }

    return result;
}

/// Frontier (July, 2015)
///
/// Genesis fork
pub const FRONTIER = Spec{
    .fork = .FRONTIER,
    .base_fork = null, // Genesis fork, no base
    .chain_id = 1, // Ethereum mainnet
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            _ = spec;
            // Frontier base costs - all opcodes that existed in the genesis fork

            // 0x00-0x0B: Arithmetic Operations
            costs[@intFromEnum(Opcode.STOP)] = FixedGasCosts.ZERO;
            costs[@intFromEnum(Opcode.ADD)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.MUL)] = FixedGasCosts.LOW;
            costs[@intFromEnum(Opcode.SUB)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.DIV)] = FixedGasCosts.LOW;
            costs[@intFromEnum(Opcode.SDIV)] = FixedGasCosts.LOW;
            costs[@intFromEnum(Opcode.MOD)] = FixedGasCosts.LOW;
            costs[@intFromEnum(Opcode.SMOD)] = FixedGasCosts.LOW;
            costs[@intFromEnum(Opcode.ADDMOD)] = FixedGasCosts.MID;
            costs[@intFromEnum(Opcode.MULMOD)] = FixedGasCosts.MID;
            costs[@intFromEnum(Opcode.EXP)] = FixedGasCosts.HIGH;
            costs[@intFromEnum(Opcode.SIGNEXTEND)] = FixedGasCosts.LOW;

            // 0x10-0x1A: Comparison & Bitwise Operations (excluding SHL/SHR/SAR)
            costs[@intFromEnum(Opcode.LT)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.GT)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.SLT)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.SGT)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.EQ)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.ISZERO)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.AND)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.OR)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.XOR)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.NOT)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.BYTE)] = FixedGasCosts.VERYLOW;
            // Note: SHL, SHR, SAR added in Constantinople

            // 0x20: Cryptographic Operations
            costs[@intFromEnum(Opcode.KECCAK256)] = 30;

            // 0x30-0x3D: Environmental Information (excluding RETURNDATASIZE/COPY, EXTCODEHASH)
            costs[@intFromEnum(Opcode.ADDRESS)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.BALANCE)] = 20;
            costs[@intFromEnum(Opcode.ORIGIN)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.CALLER)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.CALLVALUE)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.CALLDATALOAD)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.CALLDATASIZE)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.CALLDATACOPY)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.CODESIZE)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.CODECOPY)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.GASPRICE)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.EXTCODESIZE)] = 20;
            costs[@intFromEnum(Opcode.EXTCODECOPY)] = 20;
            // Note: RETURNDATASIZE, RETURNDATACOPY added in Byzantium
            // Note: EXTCODEHASH added in Istanbul

            // 0x40-0x45: Block Information (excluding CHAINID, SELFBALANCE, BASEFEE, BLOBHASH, BLOBBASEFEE)
            costs[@intFromEnum(Opcode.BLOCKHASH)] = 20;
            costs[@intFromEnum(Opcode.COINBASE)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.TIMESTAMP)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.NUMBER)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.PREVRANDAO)] = FixedGasCosts.BASE; // Was DIFFICULTY
            costs[@intFromEnum(Opcode.GASLIMIT)] = FixedGasCosts.BASE;
            // Note: CHAINID, SELFBALANCE added in Istanbul
            // Note: BASEFEE added in London
            // Note: BLOBHASH, BLOBBASEFEE added in Cancun

            // 0x50-0x5B: Stack, Memory, Storage & Flow (excluding TLOAD/TSTORE/MCOPY)
            costs[@intFromEnum(Opcode.POP)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.MLOAD)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.MSTORE)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.MSTORE8)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.SLOAD)] = 50;
            costs[@intFromEnum(Opcode.SSTORE)] = 0; // Gas calculated in handler.
            costs[@intFromEnum(Opcode.JUMP)] = FixedGasCosts.MID;
            costs[@intFromEnum(Opcode.JUMPI)] = FixedGasCosts.HIGH;
            costs[@intFromEnum(Opcode.PC)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.MSIZE)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.GAS)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.JUMPDEST)] = FixedGasCosts.JUMPDEST;
            // Note: TLOAD, TSTORE added in Cancun
            // Note: MCOPY added in Cancun
            // Note: PUSH0 added in Shanghai

            // 0x60-0x7F: PUSH1-PUSH32
            var i: u8 = @intFromEnum(Opcode.PUSH1);
            while (i <= @intFromEnum(Opcode.PUSH32)) : (i += 1) {
                costs[i] = FixedGasCosts.VERYLOW;
            }

            // 0x80-0x8F: DUP1-DUP16
            i = @intFromEnum(Opcode.DUP1);
            while (i <= @intFromEnum(Opcode.DUP16)) : (i += 1) {
                costs[i] = FixedGasCosts.VERYLOW;
            }

            // 0x90-0x9F: SWAP1-SWAP16
            i = @intFromEnum(Opcode.SWAP1);
            while (i <= @intFromEnum(Opcode.SWAP16)) : (i += 1) {
                costs[i] = FixedGasCosts.VERYLOW;
            }

            // 0xA0-0xA4: Logging Operations
            costs[@intFromEnum(Opcode.LOG0)] = 375;
            costs[@intFromEnum(Opcode.LOG1)] = 375 + 375;
            costs[@intFromEnum(Opcode.LOG2)] = 375 + 2 * 375;
            costs[@intFromEnum(Opcode.LOG3)] = 375 + 3 * 375;
            costs[@intFromEnum(Opcode.LOG4)] = 375 + 4 * 375;

            // 0xF0-0xFF: System Operations (excluding DELEGATECALL, CREATE2, STATICCALL, REVERT)
            costs[@intFromEnum(Opcode.CREATE)] = 32000;
            costs[@intFromEnum(Opcode.CALL)] = 40;
            costs[@intFromEnum(Opcode.CALLCODE)] = 40;
            costs[@intFromEnum(Opcode.RETURN)] = FixedGasCosts.ZERO;
            // Note: DELEGATECALL added in Homestead
            // Note: CREATE2 added in Constantinople
            // Note: STATICCALL added in Byzantium
            // Note: REVERT added in Byzantium
            costs[@intFromEnum(Opcode.INVALID)] = FixedGasCosts.ZERO; // Consumes all gas, but base is 0
            costs[@intFromEnum(Opcode.SELFDESTRUCT)] = FixedGasCosts.ZERO;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;

            // 0x00: STOP - Halts execution
            t[@intFromEnum(Opcode.STOP)] = .{ .execute = InstructionTable.opStop, .is_control_flow = true };

            // 0x01-0x0B: Arithmetic operations
            t[@intFromEnum(Opcode.ADD)] = .{ .execute = handlers.opAdd };
            t[@intFromEnum(Opcode.MUL)] = .{ .execute = handlers.opMul };
            t[@intFromEnum(Opcode.SUB)] = .{ .execute = handlers.opSub };
            t[@intFromEnum(Opcode.DIV)] = .{ .execute = handlers.opDiv };
            t[@intFromEnum(Opcode.SDIV)] = .{ .execute = handlers.opSdiv };
            t[@intFromEnum(Opcode.MOD)] = .{ .execute = handlers.opMod };
            t[@intFromEnum(Opcode.SMOD)] = .{ .execute = handlers.opSmod };
            t[@intFromEnum(Opcode.ADDMOD)] = .{ .execute = handlers.opAddmod };
            t[@intFromEnum(Opcode.MULMOD)] = .{ .execute = handlers.opMulmod };
            t[@intFromEnum(Opcode.EXP)] = .{ .execute = handlers.opExp, .dynamicGasCost = DynamicGasCosts.opExp };
            t[@intFromEnum(Opcode.SIGNEXTEND)] = .{ .execute = handlers.opSignextend };

            // 0x10-0x1A: Comparison & bitwise operations
            t[@intFromEnum(Opcode.LT)] = .{ .execute = handlers.opLt };
            t[@intFromEnum(Opcode.GT)] = .{ .execute = handlers.opGt };
            t[@intFromEnum(Opcode.SLT)] = .{ .execute = handlers.opSlt };
            t[@intFromEnum(Opcode.SGT)] = .{ .execute = handlers.opSgt };
            t[@intFromEnum(Opcode.EQ)] = .{ .execute = handlers.opEq };
            t[@intFromEnum(Opcode.ISZERO)] = .{ .execute = handlers.opIszero };
            t[@intFromEnum(Opcode.AND)] = .{ .execute = handlers.opAnd };
            t[@intFromEnum(Opcode.OR)] = .{ .execute = handlers.opOr };
            t[@intFromEnum(Opcode.XOR)] = .{ .execute = handlers.opXor };
            t[@intFromEnum(Opcode.NOT)] = .{ .execute = handlers.opNot };
            t[@intFromEnum(Opcode.BYTE)] = .{ .execute = handlers.opByte };
            // Note: SHL(0x1B), SHR(0x1C), SAR(0x1D) added in Constantinople

            // 0x20: Crypto operations
            t[@intFromEnum(Opcode.KECCAK256)] = .{
                .execute = handlers.opKeccak256,
                .dynamicGasCost = DynamicGasCosts.opKeccak256,
            };

            // 0x30-0x3F: Environmental information
            t[@intFromEnum(Opcode.ADDRESS)] = .{ .execute = handlers.opAddress };
            t[@intFromEnum(Opcode.BALANCE)] = .{ .execute = handlers.opBalance };
            t[@intFromEnum(Opcode.ORIGIN)] = .{ .execute = handlers.opOrigin };
            t[@intFromEnum(Opcode.CALLER)] = .{ .execute = handlers.opCaller };
            t[@intFromEnum(Opcode.CALLVALUE)] = .{ .execute = handlers.opCallvalue };
            t[@intFromEnum(Opcode.CALLDATALOAD)] = .{ .execute = handlers.opCalldataload };
            t[@intFromEnum(Opcode.CALLDATASIZE)] = .{ .execute = handlers.opCalldatasize };
            t[@intFromEnum(Opcode.CALLDATACOPY)] = .{ .execute = handlers.opCalldatacopy, .dynamicGasCost = DynamicGasCosts.opCalldatacopy };
            t[@intFromEnum(Opcode.CODESIZE)] = .{ .execute = handlers.opCodesize };
            t[@intFromEnum(Opcode.CODECOPY)] = .{ .execute = handlers.opCodecopy, .dynamicGasCost = DynamicGasCosts.opCodecopy };
            t[@intFromEnum(Opcode.GASPRICE)] = .{ .execute = handlers.opGasprice };
            t[@intFromEnum(Opcode.EXTCODESIZE)] = .{ .execute = handlers.opExtcodesize };
            t[@intFromEnum(Opcode.EXTCODECOPY)] = .{ .execute = handlers.opExtcodecopy, .dynamicGasCost = DynamicGasCosts.opExtcodecopy };
            // Note: RETURNDATASIZE(0x3D), RETURNDATACOPY(0x3E) added in Byzantium
            // Note: EXTCODEHASH(0x3F) added in Constantinople

            // 0x40-0x48: Block information
            t[@intFromEnum(Opcode.BLOCKHASH)] = .{ .execute = handlers.opBlockhash };
            t[@intFromEnum(Opcode.COINBASE)] = .{ .execute = handlers.opCoinbase };
            t[@intFromEnum(Opcode.TIMESTAMP)] = .{ .execute = handlers.opTimestamp };
            t[@intFromEnum(Opcode.NUMBER)] = .{ .execute = handlers.opNumber };
            t[@intFromEnum(Opcode.PREVRANDAO)] = .{ .execute = handlers.opPrevrandao }; // Was DIFFICULTY
            t[@intFromEnum(Opcode.GASLIMIT)] = .{ .execute = handlers.opGaslimit };
            // Note: CHAINID(0x46), SELFBALANCE(0x47) added in Istanbul
            // Note: BASEFEE(0x48) added in London

            // 0x50-0x5B: Stack, memory, storage & flow operations
            t[@intFromEnum(Opcode.POP)] = .{ .execute = handlers.opPop };
            t[@intFromEnum(Opcode.MLOAD)] = .{ .execute = handlers.opMload, .dynamicGasCost = DynamicGasCosts.opMload };
            t[@intFromEnum(Opcode.MSTORE)] = .{ .execute = handlers.opMstore, .dynamicGasCost = DynamicGasCosts.opMstore };
            t[@intFromEnum(Opcode.MSTORE8)] = .{ .execute = handlers.opMstore8, .dynamicGasCost = DynamicGasCosts.opMstore8 };
            t[@intFromEnum(Opcode.SLOAD)] = .{ .execute = handlers.opSload };
            // SSTORE: dynamicGasCost = null because gas is calculated in handler.
            // SSTORE gas depends on storage write result (original/current values).
            t[@intFromEnum(Opcode.SSTORE)] = .{ .execute = handlers.opSstore };
            t[@intFromEnum(Opcode.JUMP)] = .{ .execute = handlers.opJump, .is_control_flow = true };
            t[@intFromEnum(Opcode.JUMPI)] = .{ .execute = handlers.opJumpi }; // PC change detected in step()
            t[@intFromEnum(Opcode.PC)] = .{ .execute = handlers.opPc };
            t[@intFromEnum(Opcode.MSIZE)] = .{ .execute = handlers.opMsize };
            t[@intFromEnum(Opcode.GAS)] = .{ .execute = handlers.opGas };
            t[@intFromEnum(Opcode.JUMPDEST)] = .{ .execute = InstructionTable.opJumpdest };
            // Note: TLOAD(0x5C), TSTORE(0x5D) added in Cancun
            // Note: MCOPY(0x5E) added in Cancun
            // Note: PUSH0(0x5F) added in Shanghai

            // 0x60-0x7F: PUSH1-PUSH32
            var i: u8 = @intFromEnum(Opcode.PUSH1);
            while (i <= @intFromEnum(Opcode.PUSH32)) : (i += 1) {
                t[i] = .{ .execute = handlers.opPushN };
            }

            // 0x80-0x8F: DUP1-DUP16
            i = @intFromEnum(Opcode.DUP1);
            while (i <= @intFromEnum(Opcode.DUP16)) : (i += 1) {
                t[i] = .{ .execute = handlers.opDupN };
            }

            // 0x90-0x9F: SWAP1-SWAP16
            i = @intFromEnum(Opcode.SWAP1);
            while (i <= @intFromEnum(Opcode.SWAP16)) : (i += 1) {
                t[i] = .{ .execute = handlers.opSwapN };
            }

            // 0xA0-0xA4: Logging operations
            t[@intFromEnum(Opcode.LOG0)] = .{ .execute = handlers.opLog0, .dynamicGasCost = DynamicGasCosts.opLog0 };
            t[@intFromEnum(Opcode.LOG1)] = .{ .execute = handlers.opLog1, .dynamicGasCost = DynamicGasCosts.opLog1 };
            t[@intFromEnum(Opcode.LOG2)] = .{ .execute = handlers.opLog2, .dynamicGasCost = DynamicGasCosts.opLog2 };
            t[@intFromEnum(Opcode.LOG3)] = .{ .execute = handlers.opLog3, .dynamicGasCost = DynamicGasCosts.opLog3 };
            t[@intFromEnum(Opcode.LOG4)] = .{ .execute = handlers.opLog4, .dynamicGasCost = DynamicGasCosts.opLog4 };

            // 0xF0-0xFF: System operations
            t[@intFromEnum(Opcode.CREATE)] = .{ .execute = handlers.opCreate, .dynamicGasCost = DynamicGasCosts.opCreate };
            t[@intFromEnum(Opcode.CALL)] = .{ .execute = handlers.opCall, .dynamicGasCost = DynamicGasCosts.opCall };
            t[@intFromEnum(Opcode.CALLCODE)] = .{ .execute = handlers.opCallcode, .dynamicGasCost = DynamicGasCosts.opCallcode };
            t[@intFromEnum(Opcode.RETURN)] = .{ .execute = handlers.opReturn, .dynamicGasCost = DynamicGasCosts.opReturn, .is_control_flow = true };
            // Note: DELEGATECALL(0xF4) added in Homestead
            // Note: CREATE2(0xF5) added in Constantinople
            // Note: STATICCALL(0xFA) added in Byzantium
            // Note: REVERT(0xFD) added in Byzantium
            t[@intFromEnum(Opcode.INVALID)] = .{ .execute = InstructionTable.opInvalid, .is_control_flow = true };
            t[@intFromEnum(Opcode.SELFDESTRUCT)] = .{ .execute = handlers.opSelfdestruct, .is_control_flow = true };
        }
    }.f,
    // TODO: review and prune, base cost is calculated in updateCosts.
    .max_refund_quotient = 2,
    .sstore_clears_schedule = 15000,
    .selfdestruct_refund = 24000,
    .cold_sload_cost = 50,
    .cold_account_access_cost = 0,
    .warm_storage_read_cost = 50,
    .max_initcode_size = null,
    .initcode_word_cost = 0,
    .max_code_size = 24576,
    .has_push0 = false,
    .has_basefee = false,
    .has_prevrandao = false,
    .has_selfdestruct = true,
    .has_blob_opcodes = false,
    .has_tstore = false,
    .has_mcopy = false,
    .has_base_fee = false,
    .has_blob_gas = false,
    .target_blobs_per_block = 0,
    .max_blobs_per_block = 0,
    .has_eip7702 = false,
    .has_bls_precompiles = false,
    .has_historical_block_hashes = false,
};

/// Frontier Thawing (September, 2015)
///
/// Difficulty adjustment
pub const FRONTIER_THAWING = FRONTIER;

/// Homestead (March, 2016)
///
/// EIP-2: makes edits to contract creation process.
/// EIP-7: adds new opcode: DELEGATECALL
/// EIP-8: introduces devp2p forward compatibility requirements
pub const HOMESTEAD = forkSpec(.HOMESTEAD, FRONTIER, .{
    .cold_account_access_cost = 700, // Pre-EIP-2929 flat cost
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            _ = spec;
            // EIP-7: DELEGATECALL opcode
            costs[@intFromEnum(Opcode.DELEGATECALL)] = 40;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            t[@intFromEnum(Opcode.DELEGATECALL)] = .{ .execute = handlers.opDelegatecall, .dynamicGasCost = DynamicGasCosts.opDelegatecall };
        }
    }.f,
});

/// DAO Fork (July 2016)
///
/// State change to return stolen funds
pub const DAO_FORK = HOMESTEAD;

/// Tangerine Whistle (October 2016)
///
/// EIP-150: increases gas costs of opcodes that can be used in spam attacks.
/// EIP-158: reduces state size by removing a large number of empty accounts.
pub const TANGERINE = forkSpec(.TANGERINE, HOMESTEAD, .{
    .cold_sload_cost = 200, // EIP-150
    .sload_gas = 200, // EIP-2200: Tracks cold_sload_cost pre-Berlin
    .cold_account_access_cost = 0,
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            _ = spec;
            // EIP-150: Increase gas costs for state access opcodes to prevent DOS attacks
            costs[@intFromEnum(Opcode.BALANCE)] = 400; // Was 20
            costs[@intFromEnum(Opcode.EXTCODESIZE)] = 700; // Was 20
            costs[@intFromEnum(Opcode.EXTCODECOPY)] = 700; // Was 20
            costs[@intFromEnum(Opcode.SLOAD)] = 200; // Was 50
            costs[@intFromEnum(Opcode.CALL)] = 700; // Was 40
            costs[@intFromEnum(Opcode.CALLCODE)] = 700; // Was 40
            costs[@intFromEnum(Opcode.DELEGATECALL)] = 700; // Was 40 (Homestead introduced it)
            costs[@intFromEnum(Opcode.SELFDESTRUCT)] = 5000; // Was 0
        }
    }.f,
});

/// Spurious Dragon (November, 2016)
///
/// EIP-155: prevents transactions from one Ethereum chain from being rebroadcasted on an alternative chain, for example a testnet transaction being replayed on the main Ethereum chain.
/// EIP-160: adjusts prices of EXP opcode - makes it more difficult to slow down the network via computationally expensive contract operations.
/// EIP-161: allows for removal of empty accounts added via the DOS attacks.
/// EIP-170: changes the maximum code size that a contract on the blockchain can have - to 24576 bytes.
pub const SPURIOUS_DRAGON = forkSpec(.SPURIOUS_DRAGON, TANGERINE, .{});

/// Byzantium (October, 2017)
/// EIP-140: adds REVERT opcode.
/// EIP-658: status field added to transaction receipts to indicate success or failure.
/// EIP-196: adds elliptic curve and scalar multiplication to allow for ZK-Snarks.
/// EIP-197: adds elliptic curve and scalar multiplication to allow for ZK-Snarks.
/// EIP-198: enables RSA signature verification.
/// EIP-211: adds support for variable length return values.
/// EIP-214: adds STATICCALL opcode, allowing non-state-changing calls to other contracts.
/// EIP-100: changes difficulty adjustment formula.
/// EIP-649: delays difficulty bomb by 1 year and reduces block reward from 5 to 3 ETH.
pub const BYZANTIUM = forkSpec(.BYZANTIUM, SPURIOUS_DRAGON, .{
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            _ = spec;
            // EIP-211: RETURNDATASIZE and RETURNDATACOPY
            costs[@intFromEnum(Opcode.RETURNDATASIZE)] = FixedGasCosts.BASE;
            costs[@intFromEnum(Opcode.RETURNDATACOPY)] = FixedGasCosts.VERYLOW;
            // EIP-214: STATICCALL opcode
            costs[@intFromEnum(Opcode.STATICCALL)] = 700;
            // EIP-140: REVERT opcode
            costs[@intFromEnum(Opcode.REVERT)] = FixedGasCosts.ZERO;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            t[@intFromEnum(Opcode.RETURNDATASIZE)] = .{ .execute = handlers.opReturndatasize };
            t[@intFromEnum(Opcode.RETURNDATACOPY)] = .{ .execute = handlers.opReturndatacopy, .dynamicGasCost = DynamicGasCosts.opReturndatacopy };
            t[@intFromEnum(Opcode.STATICCALL)] = .{ .execute = handlers.opStaticcall, .dynamicGasCost = DynamicGasCosts.opStaticcall };
            t[@intFromEnum(Opcode.REVERT)] = .{ .execute = handlers.opRevert, .dynamicGasCost = DynamicGasCosts.opRevert, .is_control_flow = true };
        }
    }.f,
});

/// Constantinople (February, 2019)
///
/// EIP-145: optimises cost of certain onchain actions.
/// EIP-1014: allows you to interact with addresses that have yet to be created.
/// EIP-1052: introduces the EXTCODEHASH instruction to retrieve the hash of another contract's code.
/// EIP-1234: makes sure the blockchain doesn't freeze before proof-of-stake and reduces block reward from 3 to 2 ETH.
/// EIP-1283: Net gas metering for SSTORE without dirty maps
pub const CONSTANTINOPLE = forkSpec(.CONSTANTINOPLE, BYZANTIUM, .{
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            _ = spec;

            // EIP-145: Bitwise shifting instructions
            costs[@intFromEnum(Opcode.SHL)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.SHR)] = FixedGasCosts.VERYLOW;
            costs[@intFromEnum(Opcode.SAR)] = FixedGasCosts.VERYLOW;

            // EIP-1014: CREATE2 opcode
            costs[@intFromEnum(Opcode.CREATE2)] = 32000;

            // EIP-1052: EXTCODEHASH opcode
            costs[@intFromEnum(Opcode.EXTCODEHASH)] = 400;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            t[@intFromEnum(Opcode.SHL)] = .{ .execute = handlers.opShl };
            t[@intFromEnum(Opcode.SHR)] = .{ .execute = handlers.opShr };
            t[@intFromEnum(Opcode.SAR)] = .{ .execute = handlers.opSar };
            t[@intFromEnum(Opcode.EXTCODEHASH)] = .{ .execute = handlers.opExtcodehash };
            t[@intFromEnum(Opcode.CREATE2)] = .{ .execute = handlers.opCreate2, .dynamicGasCost = DynamicGasCosts.opCreate2 };
        }
    }.f,
});

/// Petersburg (February 2019)
///
/// Constantinople with EIP-1283 removed.
/// Includes: EIP-145 (SHL/SHR/SAR), EIP-1014 (CREATE2), EIP-1052 (EXTCODEHASH)
/// Note: Since EIP-1283 is not implemented in this codebase, Petersburg is
/// functionally identical to Constantinople.
pub const PETERSBURG = CONSTANTINOPLE;

/// Istanbul (December, 2019)
///
/// EIP-152: allow Ethereum to work with privacy-preserving currency like Zcash.
/// EIP-1108: cheaper cryptography to improve gas costs.
/// EIP-1344: protects Ethereum against replay attacks by adding CHAINID opcode.
/// EIP-1884: optimising opcode gas prices based on consumption.
/// EIP-2028: reduces the cost of CallData to allow more data in blocks - good for Layer 2 scaling.
/// EIP-2200: other opcode gas price alterations.
pub const ISTANBUL = forkSpec(.ISTANBUL, PETERSBURG, .{
    .cold_sload_cost = 800, // EIP-1884
    .sload_gas = 800, // EIP-2200: Tracks cold_sload_cost pre-Berlin
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            _ = spec;

            // EIP-1884: Increase cost of SLOAD and adjust costs
            costs[@intFromEnum(Opcode.SLOAD)] = 800; // Was 200
            costs[@intFromEnum(Opcode.BALANCE)] = 700; // Was 400

            // EIP-1052: EXTCODEHASH opcode (new opcode + cost adjustment)
            costs[@intFromEnum(Opcode.EXTCODEHASH)] = 700;

            // EIP-1344: CHAINID opcode
            costs[@intFromEnum(Opcode.CHAINID)] = FixedGasCosts.BASE;

            // EIP-1884: SELFBALANCE opcode
            costs[@intFromEnum(Opcode.SELFBALANCE)] = FixedGasCosts.LOW;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            t[@intFromEnum(Opcode.CHAINID)] = .{ .execute = handlers.opChainid };
            t[@intFromEnum(Opcode.SELFBALANCE)] = .{ .execute = handlers.opSelfbalance };
        }
    }.f,
});

/// Muir Glacier (January, 2020)
///
/// EIP-2384: delays the difficulty bomb for another 4,000,000 blocks, or ~611 days.
pub const MUIR_GLACIER = ISTANBUL;

/// Berlin (April, 2021)
///
/// EIP-2565: lowers ModExp gas cost
/// EIP-2718: enables easier support for multiple transaction types
/// EIP-2929: gas cost increases for state access opcodes
/// EIP-2930: adds optional access lists
pub const BERLIN = forkSpec(.BERLIN, ISTANBUL, .{
    .cold_sload_cost = 2100, // EIP-2929: Cold storage access
    .cold_account_access_cost = 2600, // EIP-2929: Cold account access
    .warm_storage_read_cost = 100, // EIP-2929: Warm access
    .sload_gas = 100, // EIP-2200: Now uses warm cost (SSTORE assumes warm access)
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            // EIP-2929: Warm/cold storage access costs
            // These are the warm (already accessed) costs
            costs[@intFromEnum(Opcode.BALANCE)] = spec.warm_storage_read_cost; // 100
            costs[@intFromEnum(Opcode.EXTCODESIZE)] = spec.warm_storage_read_cost;
            costs[@intFromEnum(Opcode.EXTCODECOPY)] = spec.warm_storage_read_cost;
            costs[@intFromEnum(Opcode.EXTCODEHASH)] = spec.warm_storage_read_cost;
            costs[@intFromEnum(Opcode.SLOAD)] = spec.warm_storage_read_cost;
            costs[@intFromEnum(Opcode.CALL)] = spec.warm_storage_read_cost;
            costs[@intFromEnum(Opcode.CALLCODE)] = spec.warm_storage_read_cost;
            costs[@intFromEnum(Opcode.DELEGATECALL)] = spec.warm_storage_read_cost;
            costs[@intFromEnum(Opcode.STATICCALL)] = spec.warm_storage_read_cost;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            // EIP-2929: Add dynamic gas cost for state access opcodes.
            // BALANCE, EXTCODESIZE, EXTCODEHASH need warm/cold tracking.
            // EXTCODECOPY is already wired in Frontier with dynamicGasCost.
            t[@intFromEnum(Opcode.BALANCE)].dynamicGasCost = DynamicGasCosts.opBalance;
            t[@intFromEnum(Opcode.EXTCODESIZE)].dynamicGasCost = DynamicGasCosts.opExtcodesize;
            t[@intFromEnum(Opcode.EXTCODEHASH)].dynamicGasCost = DynamicGasCosts.opExtcodehash;

            // SLOAD needs warm/cold storage slot tracking.
            t[@intFromEnum(Opcode.SLOAD)].dynamicGasCost = DynamicGasCosts.opSload;
        }
    }.f,
});

/// London (August, 2021)
///
/// EIP-1559: improves the transaction fee market
/// EIP-3198: returns the BASEFEE from a block
/// EIP-3529: reduces gas refunds for EVM operations
/// EIP-3541: prevents deploying contracts starting with 0xEF
/// EIP-3554: delays the Ice Age until December 2021
pub const LONDON = forkSpec(.LONDON, BERLIN, .{
    .max_refund_quotient = 5, // EIP-3529: Changed from 2 to 5
    .sstore_clears_schedule = 4800, // EIP-3529: Reduced from 15000
    .selfdestruct_refund = 0, // EIP-3529: Removed
    .has_basefee = true, // EIP-3198
    .has_base_fee = true, // EIP-1559
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            _ = spec;
            // EIP-3198: BASEFEE opcode
            costs[@intFromEnum(Opcode.BASEFEE)] = FixedGasCosts.BASE;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            t[@intFromEnum(Opcode.BASEFEE)] = .{ .execute = handlers.opBasefee };
        }
    }.f,
});

/// Arrow Glacier (December, 2021)
///
/// EIP-4345: delays the difficulty bomb until June 2022
pub const ARROW_GLACIER = LONDON;

/// Gray Glacier (June, 2022)
///
/// EIP-5133: delays the difficulty bomb until September 2022
pub const GRAY_GLACIER = LONDON;

/// Paris/Merge (September, 2022)
///
/// EIP-3675: Upgrade consensus to Proof-of-Stake
/// EIP-4399: Supplant DIFFICULTY opcode with PREVRANDAO
pub const MERGE = forkSpec(.MERGE, LONDON, .{
    .has_prevrandao = true, // EIP-4399: DIFFICULTY → PREVRANDAO
});

/// Shanghai (April, 2023)
///
/// EIP-3651: Starts the COINBASE address warm
/// EIP-3855: New PUSH0 instruction
/// EIP-3860: Limit and meter initcode
/// EIP-4895: Beacon chain push withdrawals as operations
/// EIP-6049: Deprecate SELFDESTRUCT
pub const SHANGHAI = forkSpec(.SHANGHAI, MERGE, .{
    .max_initcode_size = 49152, // EIP-3860: 2 * max_code_size
    .initcode_word_cost = 2, // EIP-3860
    .has_push0 = true, // EIP-3855
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            _ = spec;

            // EIP-3855: PUSH0 instruction
            costs[@intFromEnum(Opcode.PUSH0)] = FixedGasCosts.BASE;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            t[@intFromEnum(Opcode.PUSH0)] = .{ .execute = handlers.opPush0 };
        }
    }.f,
});

/// Cancun (March, 2024)
///
/// EIP-1153: Transient storage opcodes
/// EIP-4788: Beacon block root in the EVM
/// EIP-4844: Shard blob transactions (Proto-Danksharding)
/// EIP-5656: MCOPY - Memory copying instruction
/// EIP-6780: SELFDESTRUCT only in same transaction
/// EIP-7516: BLOBBASEFEE opcode
pub const CANCUN = forkSpec(.CANCUN, SHANGHAI, .{
    .has_blob_opcodes = true, // EIP-4844
    .has_tstore = true, // EIP-1153
    .has_mcopy = true, // EIP-5656
    .has_blob_gas = true, // EIP-4844
    .target_blobs_per_block = 3, // EIP-4844
    .max_blobs_per_block = 6, // EIP-4844
    .updateCosts = struct {
        fn f(costs: *[256]u64, spec: Spec) void {
            _ = spec;

            // EIP-1153: Transient storage opcodes
            costs[@intFromEnum(Opcode.TLOAD)] = 100;
            costs[@intFromEnum(Opcode.TSTORE)] = 100;

            // EIP-5656: MCOPY instruction
            costs[@intFromEnum(Opcode.MCOPY)] = FixedGasCosts.VERYLOW;

            // EIP-4844: Blob opcodes
            costs[@intFromEnum(Opcode.BLOBHASH)] = FixedGasCosts.VERYLOW;

            // EIP-7516: BLOBBASEFEE opcode
            costs[@intFromEnum(Opcode.BLOBBASEFEE)] = FixedGasCosts.BASE;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            t[@intFromEnum(Opcode.TLOAD)] = .{ .execute = handlers.opTload };
            t[@intFromEnum(Opcode.TSTORE)] = .{ .execute = handlers.opTstore };
            t[@intFromEnum(Opcode.MCOPY)] = .{ .execute = handlers.opMcopy, .dynamicGasCost = DynamicGasCosts.opMcopy };
            t[@intFromEnum(Opcode.BLOBHASH)] = .{ .execute = handlers.opBlobhash };
            t[@intFromEnum(Opcode.BLOBBASEFEE)] = .{ .execute = handlers.opBlobbasefee };
        }
    }.f,
});

/// Prague (May, 2025)
///
/// Better user experience:
/// EIP-7702: Set EOA account code
/// EIP-7691: Blob throughput increase
/// EIP-7623: Increase calldata cost
/// EIP-7840: Add blob schedule to EL config files
///
/// Better staking experience:
/// EIP-7251: Increase the MAX_EFFECTIVE_BALANCE
/// EIP-7002: Execution layer triggerable exits
/// EIP-7685: General purpose execution layer requests
/// EIP-6110: Supply validator deposits on chain
///
/// Protocol efficiency and security improvements:
/// EIP-2537: Precompile for BLS12-381 curve operations
/// EIP-2935: Save historical block hashes in state
/// EIP-7549: Move committee index outside Attestation
pub const PRAGUE = forkSpec(.PRAGUE, CANCUN, .{
    .target_blobs_per_block = 6, // EIP-7691: Doubled from 3
    .max_blobs_per_block = 9, // EIP-7691: Increased from 6
    .has_eip7702 = true, // EIP-7702: EOA account abstraction
    .has_bls_precompiles = true, // EIP-2537: BLS12-381 curve operations
    .has_historical_block_hashes = true, // EIP-2935: 8192 block hashes
});

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Hardfork: ordering" {
    try expect(Hardfork.FRONTIER.isBefore(.HOMESTEAD));
    try expect(Hardfork.BERLIN.isBefore(.LONDON));
    try expect(Hardfork.LONDON.isAtLeast(.BERLIN));
    try expect(Hardfork.CANCUN.isAtLeast(.CANCUN));
}

test "Hardfork: name" {
    try expectEqual("Frontier", Hardfork.FRONTIER.name());
    try expectEqual("London", Hardfork.LONDON.name());
    try expectEqual("Cancun", Hardfork.CANCUN.name());
}

test "Spec: forFork" {
    const frontier = Spec.forFork(.FRONTIER);
    try expectEqual(Hardfork.FRONTIER, frontier.fork);

    const london = Spec.forFork(.LONDON);
    try expectEqual(Hardfork.LONDON, london.fork);
}

test "Spec: hasEIP - EIP-3529" {
    const berlin = BERLIN;
    const london = LONDON;

    // EIP-3529 not in Berlin
    try expect(!berlin.hasEIP(3529));
    try expectEqual(2, berlin.max_refund_quotient);

    // EIP-3529 in London
    try expect(london.hasEIP(3529));
    try expectEqual(5, london.max_refund_quotient);
}

test "Spec: hasEIP - EIP-3855 PUSH0" {
    const london = LONDON;
    const shanghai = SHANGHAI;

    try expect(!london.hasEIP(3855));
    try expect(shanghai.hasEIP(3855));
}

test "Spec: hasEIP - EIP-2929" {
    const homestead = HOMESTEAD;
    const berlin = BERLIN;

    try expect(!homestead.hasEIP(2929));
    try expect(berlin.hasEIP(2929));
}

test "Spec: refund changes across forks" {
    // Berlin: refund cap = used/2
    try expectEqual(2, BERLIN.max_refund_quotient);
    try expectEqual(15000, BERLIN.sstore_clears_schedule);
    try expectEqual(24000, BERLIN.selfdestruct_refund);

    // London: refund cap = used/5, reduced refunds
    try expectEqual(5, LONDON.max_refund_quotient);
    try expectEqual(4800, LONDON.sstore_clears_schedule);
    try expectEqual(0, LONDON.selfdestruct_refund);
}

test "Spec: SLOAD cost changes" {
    // Frontier/Homestead: 50
    try expectEqual(50, FRONTIER.cold_sload_cost);
    try expectEqual(50, HOMESTEAD.cold_sload_cost);

    // Tangerine: 200 (EIP-150)
    try expectEqual(200, TANGERINE.cold_sload_cost);

    // Istanbul: 800 (EIP-1884)
    try expectEqual(800, ISTANBUL.cold_sload_cost);

    // Berlin: 2100 cold, 100 warm (EIP-2929)
    try expectEqual(2100, BERLIN.cold_sload_cost);
    try expectEqual(100, BERLIN.warm_storage_read_cost);
}

test "Spec: opcode availability" {
    const london = LONDON;
    const merge = MERGE;
    const shanghai = SHANGHAI;
    const cancun = CANCUN;

    // PUSH0 only in Shanghai+
    try expect(!london.has_push0);
    try expect(shanghai.has_push0);

    // BASEFEE in London+
    try expect(london.has_basefee);

    // PREVRANDAO in Merge+
    try expect(!london.has_prevrandao);
    try expect(merge.has_prevrandao);

    // Blob opcodes in Cancun+
    try expect(!shanghai.has_blob_opcodes);
    try expect(cancun.has_blob_opcodes);

    // Transient storage in Cancun+
    try expect(!shanghai.has_tstore);
    try expect(cancun.has_tstore);
}
