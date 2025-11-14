const std = @import("std");

pub const Host = @import("Host.zig");
pub const MockHost = @import("mock.zig").MockHost;

test {
    std.testing.refAllDecls(@This());
    _ = @import("mock.zig");
}
