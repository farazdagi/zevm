//! Environmental context for EVM execution.
//!
//! Separates immutable blockchain context (BlockEnv, TxEnv) from mutable state operations (Host).

const std = @import("std");
const Address = @import("primitives/mod.zig").Address;
const U256 = @import("primitives/mod.zig").U256;
const B256 = @import("primitives/mod.zig").B256;

/// Block-level environmental information.
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
    /// ZERO for pre-London forks.
    basefee: U256 = U256.ZERO,

    /// PREVRANDAO value (post-Merge) or difficulty (pre-Merge).
    prevrandao: B256,

    /// Chain ID (EIP-155)
    chain_id: u64,

    /// Convenient defaults for testing and prototyping.
    /// Returns minimal valid environment (mainnet, block 1).
    pub fn default() BlockEnv {
        return .{
            .number = 1,
            .coinbase = Address.zero(),
            .timestamp = 0,
            .gas_limit = 30_000_000,
            .basefee = U256.ZERO,
            .prevrandao = B256.zero(),
            .chain_id = 1, // Ethereum mainnet
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

    /// Convenient defaults for testing and prototyping.
    /// Returns zero addresses and values.
    pub fn default() TxEnv {
        return .{
            .caller = Address.zero(),
            .origin = Address.zero(),
            .gas_price = U256.ZERO,
            .value = U256.ZERO,
            .data = &[_]u8{},
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
