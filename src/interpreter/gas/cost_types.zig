//! Complex gas cost type definitions that evolved across multiple forks.
//!
//! Defines type definitions (tagged unions, structs) for cost calculations
//! that underwent not just a value changes, but a more structural changes
//! in how the cost is calculated across different hard forks.
//!
//! Each such complex calculation requires different inputs and logic, so we use
//! a tagged union type to represent this evolution type-safely.

/// SSTORE cost model.
///
/// SSTORE costs evolved through three distinct models:
/// 1. Simple (Frontier-Byzantium): Basic set/reset costs
/// 2. Net Metered (Istanbul, EIP-2200): Track original/current/new for refunds
/// 3. With Cold Access (Berlin+, EIP-2929): Add cold/warm access distinction
pub const SstoreCost = union(enum) {
    /// Simple set/reset model (Frontier-Byzantium).
    simple: struct {
        /// Zero -> non-zero
        /// SSTORE_SET_GAS = 20000
        set_gas: u64,

        /// Non-zero -> non-zero
        /// SSTORE_RESET_GAS = 5000
        reset_gas: u64,

        /// Refund when non-zero -> zero
        /// SSTORE_CLEARS_SCHEDULE = 15000
        clears_schedule: u64,
    },

    /// EIP-2200 (Istanbul): Structured Definitions for Net Gas Metering
    ///
    /// While conceptually parameters existed, now they are formally introduced.
    net_metered: struct {
        /// Cost to read slot (used for dirty slots)
        /// SLOAD_GAS = 800 (previously: 200)
        sload_gas: u64,

        /// Not changed, but formally introduced.
        set_gas: u64,
        reset_gas: u64,
        clears_schedule: u64,
    },

    /// EIP-2929 (Berlin): Gas cost increases for state access opcodes.
    ///
    /// Added cold/warm access distinction on top of net metering:
    /// - First access to slot: cold cost (2100 gas)
    /// - Subsequent accesses: warm cost (100 gas)
    /// - London (EIP-3529) reduced refund from 15,000 -> 4,800
    ///
    /// Note: Berlin changed the underlying cost but kept net metering logic.
    with_cold_access: struct {
        // First access to storage slot in a transaction.
        // COLD_SLOAD_COST = 2100
        cold_sload_cost: u64,

        // Subsequent accesses.
        // SLOAD_GAS = WARM_STORAGE_READ_COST (100)
        sload_gas: u64,

        // 20000 (not changed)
        set_gas: u64,

        /// SSTORE_RESET_GAS = 5000 - COLD_SLOAD_COST
        reset_gas: u64,

        // 15,000 (Berlin) or 4,800 (London+)
        clears_schedule: u64,

        // First access to an account.
        // COLD_ACCOUNT_ACCESS_COST = 2600
        cold_account_access_cost: u64,
    },
};
