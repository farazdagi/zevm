//! Main Zevm library.

const std = @import("std");
pub const primitives = @import("primitives/mod.zig");
pub const interpreter = @import("interpreter/mod.zig");
pub const Spec = @import("Spec.zig");
pub const gas = @import("gas/mod.zig");
pub const context = @import("context.zig");
pub const host = @import("host/mod.zig");
pub const CallExecutor = @import("CallExecutor.zig");
pub const evm = @import("evm.zig");
pub const Evm = evm.Evm;
pub const Contract = @import("Contract.zig");
pub const AccessList = @import("AccessList.zig");
pub const AccessListAccessor = AccessList.Accessor;
pub const Log = @import("Log.zig");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Import tests
test {
    std.testing.refAllDecls(@This());
    _ = primitives;
    _ = interpreter;
    _ = Spec;
    _ = gas;
    _ = context;
    _ = host;
    _ = CallExecutor;
    _ = Evm;
    _ = AccessList;
    _ = Log;
}
