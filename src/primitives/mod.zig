const std = @import("std");

pub const address = @import("address.zig");
pub const bytes = @import("bytes.zig");
pub const big = @import("big.zig");
pub const rlp = @import("rlp.zig");

// Re-export commonly used primitives
pub const Address = address.Address;
pub const B256 = bytes.B256;
pub const B160 = bytes.B160;
pub const FixedBytes = bytes.FixedBytes;
pub const Bytes = bytes.Bytes;
pub const U256 = big.U256;

// Re-export RLP encoding function
pub const encodeAddressNonce = rlp.encodeAddressNonce;

test {
    std.testing.refAllDecls(@This());
}
