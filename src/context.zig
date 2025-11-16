//! Environmental context for EVM execution.
//!
//! Separates immutable blockchain context (BlockEnv, TxEnv) from mutable state operations (Host).

const std = @import("std");
const Address = @import("primitives/mod.zig").Address;
const U256 = @import("primitives/mod.zig").U256;
const B256 = @import("primitives/mod.zig").B256;

/// Block-level environmental information.
///
/// For instructions that need to know runtime per-block data of a block that is being processed.
pub const BlockEnv = struct {
    /// Block number
    number: u64,

    /// Coinbase address (miner/validator).
    coinbase: Address,

    /// Block timestamp (Unix seconds).
    timestamp: u64,

    /// Block gas limit.
    gas_limit: u64,

    /// Base fee per gas (EIP-1559, London+).
    ///
    /// Calculated per block based on parent block's gas usage.
    /// ZERO for pre-London forks.
    basefee: U256 = U256.ZERO,

    /// PREVRANDAO value (post-Merge) or difficulty (pre-Merge).
    ///
    /// Post-merge: random value from beacon chain (changes every block).
    /// Pre-merge: difficulty value.
    prevrandao: B256,

    /// Blob base fee (EIP-4844, Cancun+).
    ///
    /// Calculated per block based on excess blob gas.
    /// ZERO for pre-Cancun forks.
    blob_basefee: U256 = U256.ZERO,

    /// Convenient defaults for testing and prototyping.
    /// Returns minimal valid block environment.
    pub fn default() BlockEnv {
        return .{
            .number = 1,
            .coinbase = Address.zero(),
            .timestamp = 0,
            .gas_limit = 30_000_000,
            .basefee = U256.ZERO,
            .prevrandao = B256.zero(),
            .blob_basefee = U256.ZERO,
        };
    }
};

/// Transaction-level environmental information.
pub const TxEnv = struct {
    /// Transaction caller (msg.sender).
    caller: Address,

    /// Transaction origin (tx.origin).
    origin: Address,

    /// Gas price.
    gas_price: U256,

    /// Value transferred (msg.value).
    value: U256,

    /// Input data (calldata).
    data: []const u8,

    /// Blob versioned hashes (EIP-4844, Cancun+).
    ///
    /// Contains the versioned hashes of blobs committed to in this transaction.
    /// Empty for pre-Cancun forks or transactions without blobs.
    blob_hashes: []const B256 = &[_]B256{},

    /// Convenient defaults for testing and prototyping.
    /// Returns zero addresses and values.
    pub fn default() TxEnv {
        return .{
            .caller = Address.zero(),
            .origin = Address.zero(),
            .gas_price = U256.ZERO,
            .value = U256.ZERO,
            .data = &[_]u8{},
            .blob_hashes = &[_]B256{},
        };
    }
};

/// Complete environmental context.
pub const Env = struct {
    block: BlockEnv,
    tx: TxEnv,

    /// Convenient defaults for testing and prototyping.
    /// Returns default BlockEnv and TxEnv.
    pub fn default() Env {
        return .{
            .block = BlockEnv.default(),
            .tx = TxEnv.default(),
        };
    }
};
