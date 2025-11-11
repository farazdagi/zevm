const std = @import("std");

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

    /// EIP-3860: Limit and meter initcode
    /// Maximum initcode size (null = no limit)
    max_initcode_size: ?usize,

    /// Cost per word of initcode
    initcode_word_cost: u64,

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
    .max_refund_quotient = 2,
    .sstore_clears_schedule = 15000,
    .selfdestruct_refund = 24000,
    .cold_sload_cost = 200,
    .cold_account_access_cost = 0,
    .warm_storage_read_cost = 200,
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
    .cold_account_access_cost = 0,
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
pub const BYZANTIUM = SPURIOUS_DRAGON;

/// Constantinople (February, 2019)
///
/// EIP-145: optimises cost of certain onchain actions.
/// EIP-1014: allows you to interact with addresses that have yet to be created.
/// EIP-1052: introduces the EXTCODEHASH instruction to retrieve the hash of another contract's code.
/// EIP-1234: makes sure the blockchain doesn't freeze before proof-of-stake and reduces block reward from 3 to 2 ETH.
/// EIP-1283: Net gas metering for SSTORE without dirty maps
pub const CONSTANTINOPLE = SPURIOUS_DRAGON;

/// Petersburg (February 2019)
///
/// Removed EIP-1283
pub const PETERSBURG = SPURIOUS_DRAGON;

/// Istanbul (December, 2019)
///
/// EIP-152: allow Ethereum to work with privacy-preserving currency like Zcash.
/// EIP-1108: cheaper cryptography to improve gas costs.
/// EIP-1344: protects Ethereum against replay attacks by adding CHAINID opcode.
/// EIP-1884: optimising opcode gas prices based on consumption.
/// EIP-2028: reduces the cost of CallData to allow more data in blocks - good for Layer 2 scaling.
/// EIP-2200: other opcode gas price alterations.
pub const ISTANBUL = forkSpec(.ISTANBUL, SPURIOUS_DRAGON, .{});

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
    .cold_sload_cost = 2100, // EIP-2929
    .cold_account_access_cost = 2600, // EIP-2929
    .warm_storage_read_cost = 100, // EIP-2929
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
    // Homestead: flat 200
    try expectEqual(200, HOMESTEAD.cold_sload_cost);

    // Berlin: 2100 cold, 100 warm
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
