//! EVM gas accounting and cost calculations.

// Re-export main types and modules
pub const Gas = @import("accounting.zig").Gas;
pub const Costs = @import("costs.zig").Costs;
pub const Calculator = @import("cost_fns.zig");
pub const SstoreCost = @import("cost_types.zig").SstoreCost;
pub const FixedGasCosts = @import("FixedGasCosts.zig");

// Run all tests in submodules
comptime {
    _ = @import("accounting.zig");
    _ = @import("cost_fns.zig");
    _ = @import("costs.zig");
    _ = @import("cost_types.zig");
    _ = @import("FixedGasCosts.zig");
}
