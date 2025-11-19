//! Main Zevm library.

const std = @import("std");
pub const primitives = @import("primitives/mod.zig");
pub const interpreter = @import("interpreter/mod.zig");
pub const hardfork = @import("hardfork.zig");
pub const gas = @import("gas/mod.zig");
pub const context = @import("context.zig");
pub const host = @import("host/mod.zig");
pub const call_types = @import("call_types.zig");
pub const CallKind = call_types.CallKind;
pub const CallInputs = call_types.CallInputs;
pub const CallResult = call_types.CallResult;
pub const CallExecutor = call_types.CallExecutor;
pub const evm = @import("evm.zig");
pub const Evm = evm.Evm;
pub const Contract = @import("Contract.zig");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Import tests
test {
    std.testing.refAllDecls(@This());
    _ = primitives;
    _ = interpreter;
    _ = hardfork;
    _ = gas;
    _ = context;
    _ = host;
    _ = call_types;
    _ = Evm;
}
