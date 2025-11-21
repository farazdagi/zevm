//! EVM gas accounting and cost calculations.

// Re-export main types and modules
pub const Gas = @import("accounting.zig").Gas;
pub const FixedGasCosts = @import("FixedGasCosts.zig");
pub const DynamicGasCosts = @import("DynamicGasCosts.zig");
pub const sstore = @import("sstore.zig");

// Run all tests in submodules
comptime {
    _ = @import("accounting.zig");
    _ = @import("FixedGasCosts.zig");
    _ = @import("DynamicGasCosts.zig");
    _ = @import("sstore.zig");
}
