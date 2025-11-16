//! Host interface for external state access.

const std = @import("std");
const Address = @import("../primitives/mod.zig").Address;
const U256 = @import("../primitives/mod.zig").U256;
const B256 = @import("../primitives/mod.zig").B256;

const Host = @This();

/// Errors that can occur during host operations.
pub const Error = error{
    /// Insufficient balance for transfer
    InsufficientBalance,
};

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

    /// Create a snapshot of current state.
    ///
    /// Returns a snapshot ID that can be used to revert to this state.
    /// Snapshot IDs are monotonic (each new snapshot gets a unique ID).
    /// Multiple snapshots can exist simultaneously.
    snapshot: *const fn (ptr: *anyopaque) std.mem.Allocator.Error!usize,

    /// Revert state to a previous snapshot.
    ///
    /// Restores all state (balances, code, nonces, storage) to the snapshot.
    /// All snapshots created after the given snapshot_id are discarded.
    /// The snapshot being reverted to remains valid for potential future reverts.
    revertToSnapshot: *const fn (ptr: *anyopaque, snapshot_id: usize) void,

    /// Transfer value between accounts.
    ///
    /// Transfers `value` from `from` address to `to` address.
    /// Returns error.InsufficientBalance if `from` has insufficient balance.
    /// Zero-value transfers should succeed without error.
    /// Creates `to` account if it doesn't exist (with transferred balance).
    transfer: *const fn (ptr: *anyopaque, from: Address, to: Address, value: U256) (std.mem.Allocator.Error || Error)!void,
};

pub inline fn balance(self: Host, address: Address) U256 {
    return self.vtable.balance(self.ptr, address);
}

pub inline fn code(self: Host, address: Address) ![]const u8 {
    return self.vtable.code(self.ptr, address);
}

pub inline fn codeHash(self: Host, address: Address) B256 {
    return self.vtable.codeHash(self.ptr, address);
}

pub inline fn codeSize(self: Host, address: Address) usize {
    return self.vtable.codeSize(self.ptr, address);
}

pub inline fn blockHash(self: Host, block_number: u64) B256 {
    return self.vtable.blockHash(self.ptr, block_number);
}

pub inline fn snapshot(self: Host) !usize {
    return self.vtable.snapshot(self.ptr);
}

pub inline fn revertToSnapshot(self: Host, snapshot_id: usize) void {
    self.vtable.revertToSnapshot(self.ptr, snapshot_id);
}

pub inline fn transfer(self: Host, from: Address, to: Address, value: U256) !void {
    return self.vtable.transfer(self.ptr, from, to, value);
}
