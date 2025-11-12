//! Pre-computed BASE gas costs for all 256 opcodes.
//!
//! This provides O(1) lookup for base gas costs.

const std = @import("std");
const hardfork = @import("../../hardfork.zig");
const Hardfork = hardfork.Hardfork;
const Spec = hardfork.Spec;

/// Gas cost tier constants (shared across all forks).
pub const ZERO: u64 = 0;
pub const BASE: u64 = 2;
pub const VERYLOW: u64 = 3;
pub const LOW: u64 = 5;
pub const MID: u64 = 8;
pub const HIGH: u64 = 10;
pub const JUMPDEST: u64 = 1;

const FixedGasCosts = @This();

/// Base gas cost per opcode byte (indexed by opcode value)
costs: [256]u64,

/// Recursively compute gas costs for a specific fork.
///
/// This builds costs incrementally: base fork costs + this fork's updates.
/// For Frontier (base_fork = null), initializes empty table.
/// For other forks, gets base fork costs and applies this fork's updateCosts().
fn computeCostsForFork(comptime spec: Spec) FixedGasCosts {
    @setEvalBranchQuota(10000);

    var table: FixedGasCosts = undefined;

    // Initialize all costs to 0 (undefined opcodes)
    for (&table.costs) |*cost| {
        cost.* = 0;
    }

    // For Frontier the table already initialized to zeros.
    // For other forks replace it with the base fork's recursively computed table.
    if (spec.base_fork) |base| {
        const base_spec = Spec.forFork(base);
        table = computeCostsForFork(base_spec);
    }

    // Apply this fork's cost updates (if any)
    if (spec.updateCosts) |updateFn| {
        updateFn(&table, spec);
    }

    return table;
}

/// Pre-computed gas cost tables for each fork.
pub const FRONTIER: FixedGasCosts = computeCostsForFork(hardfork.FRONTIER);
pub const HOMESTEAD: FixedGasCosts = computeCostsForFork(hardfork.HOMESTEAD);
pub const TANGERINE: FixedGasCosts = computeCostsForFork(hardfork.TANGERINE);
pub const SPURIOUS_DRAGON: FixedGasCosts = computeCostsForFork(hardfork.SPURIOUS_DRAGON);
pub const BYZANTIUM: FixedGasCosts = computeCostsForFork(hardfork.BYZANTIUM);
pub const CONSTANTINOPLE: FixedGasCosts = computeCostsForFork(hardfork.CONSTANTINOPLE);
pub const PETERSBURG: FixedGasCosts = computeCostsForFork(hardfork.PETERSBURG);
pub const ISTANBUL: FixedGasCosts = computeCostsForFork(hardfork.ISTANBUL);
pub const MUIR_GLACIER: FixedGasCosts = computeCostsForFork(hardfork.MUIR_GLACIER);
pub const BERLIN: FixedGasCosts = computeCostsForFork(hardfork.BERLIN);
pub const LONDON: FixedGasCosts = computeCostsForFork(hardfork.LONDON);
pub const ARROW_GLACIER: FixedGasCosts = computeCostsForFork(hardfork.ARROW_GLACIER);
pub const GRAY_GLACIER: FixedGasCosts = computeCostsForFork(hardfork.GRAY_GLACIER);
pub const MERGE: FixedGasCosts = computeCostsForFork(hardfork.MERGE);
pub const SHANGHAI: FixedGasCosts = computeCostsForFork(hardfork.SHANGHAI);
pub const CANCUN: FixedGasCosts = computeCostsForFork(hardfork.CANCUN);
pub const PRAGUE: FixedGasCosts = computeCostsForFork(hardfork.PRAGUE);

/// Get pre-computed gas cost table for a specific fork.
pub fn forFork(fork: Hardfork) FixedGasCosts {
    return switch (fork) {
        .FRONTIER => FRONTIER,
        .FRONTIER_THAWING => FRONTIER,
        .HOMESTEAD => HOMESTEAD,
        .DAO_FORK => HOMESTEAD,
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
        .OSAKA => PRAGUE, // Use Prague for future Osaka
    };
}
