//! Host interface for external state access.

const std = @import("std");
const Address = @import("../primitives/mod.zig").Address;
const U256 = @import("../primitives/mod.zig").U256;
const B256 = @import("../primitives/mod.zig").B256;

const Host = @This();

/// Opaque pointer to concrete implementation.
ptr: *anyopaque,

/// Function pointer table for host operations.
vtable: *const VTable,

/// Vtable definition for host operations
pub const VTable = struct {
    /// Get balance of an account.
    balance: *const fn (ptr: *anyopaque, address: Address) U256,

    /// Get code of an account (caller must free returned slice).
    code: *const fn (ptr: *anyopaque, address: Address) std.mem.Allocator.Error![]const u8,

    /// Get code hash of an account.
    codeHash: *const fn (ptr: *anyopaque, address: Address) B256,

    /// Get code size of an account.
    codeSize: *const fn (ptr: *anyopaque, address: Address) usize,

    /// Get hash of a block by number.
    ///
    /// Returns B256.zero() for:
    /// - Block numbers >= current block
    /// - Block numbers more than 256 blocks in the past
    /// - Non-existent blocks
    blockHash: *const fn (ptr: *anyopaque, block_number: u64) B256,
};

/// Get balance of an account.
///
/// Returns U256.ZERO for non-existent accounts (per EVM spec).
pub inline fn balance(self: Host, address: Address) U256 {
    return self.vtable.balance(self.ptr, address);
}

/// Get code of an account.
///
/// Returns empty slice for accounts without code (EOAs or non-existent).
/// Caller owns returned slice and must free it.
pub inline fn code(self: Host, address: Address) ![]const u8 {
    return self.vtable.code(self.ptr, address);
}

/// Get code hash of an account.
///
/// Returns B256.zero() for accounts without code or non-existent accounts.
pub inline fn codeHash(self: Host, address: Address) B256 {
    return self.vtable.codeHash(self.ptr, address);
}

/// Get code size of an account.
///
/// Returns 0 for accounts without code or non-existent accounts.
pub inline fn codeSize(self: Host, address: Address) usize {
    return self.vtable.codeSize(self.ptr, address);
}

/// Get hash of a block by number.
///
/// Returns B256.zero() for invalid or unavailable blocks.
/// Per EVM spec, only the most recent 256 blocks are accessible.
pub inline fn blockHash(self: Host, block_number: u64) B256 {
    return self.vtable.blockHash(self.ptr, block_number);
}
