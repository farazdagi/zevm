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

/// Result from SSTORE operation with metadata for gas calculation.
///
/// Returned by `sstore()` which performs the write AND returns value info.
/// To check whether access is cold/warm, use `AccessList.warmSlot()` before calling.
pub const SstoreResult = struct {
    /// Value at transaction start (for net metering).
    original_value: U256,

    /// Value before this SSTORE (now overwritten).
    current_value: U256,
};

/// Opaque pointer to concrete implementation.
ptr: *anyopaque,

/// Function pointer table for host operations.
vtable: *const VTable,

/// Vtable definition for host operations
pub const VTable = struct {
    /// Get balance of an account.
    balance: *const fn (ptr: *anyopaque, address: Address) U256,

    /// Get code of an account.
    ///
    /// The caller owns the returned memory and MUST free it.
    /// This always returns owned memory, even for empty code (zero-length allocation).
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

    /// Get nonce of an account.
    ///
    /// Returns the nonce value for the given address.
    /// Returns 0 for non-existent accounts (default nonce value).
    nonce: *const fn (ptr: *anyopaque, address: Address) u64,

    /// Check if an account exists.
    ///
    /// Returns true if the account exists in state (has balance, code, or nonce).
    /// Returns false if the account does not exist in any state map.
    accountExists: *const fn (ptr: *anyopaque, address: Address) bool,

    /// Load value from persistent storage.
    ///
    /// Returns the value at the given storage slot for the address.
    /// Returns U256.zero() for uninitialized slots.
    sload: *const fn (ptr: *anyopaque, address: Address, key: U256) U256,

    /// Store value to persistent storage.
    ///
    /// Writes the value to the storage slot and returns metadata for gas calculation.
    /// The returned result contains `original_value` (at tx start) and `current_value`
    /// (before this write). Cold/warm status should be tracked via AccessList.
    sstore: *const fn (ptr: *anyopaque, address: Address, key: U256, value: U256) SstoreResult,

    /// Load value from transient (cleared at the end of each tx) storage (EIP-1153).
    ///
    /// Returns the value at the given transient storage slot.
    /// Returns U256.zero() for uninitialized slots.
    tload: *const fn (ptr: *anyopaque, address: Address, key: U256) U256,

    /// Store value to transient storage (EIP-1153).
    ///
    /// Writes the value to the transient storage slot.
    tstore: *const fn (ptr: *anyopaque, address: Address, key: U256, value: U256) void,
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

pub inline fn nonce(self: Host, address: Address) u64 {
    return self.vtable.nonce(self.ptr, address);
}

pub inline fn accountExists(self: Host, address: Address) bool {
    return self.vtable.accountExists(self.ptr, address);
}

pub inline fn sload(self: Host, address: Address, key: U256) U256 {
    return self.vtable.sload(self.ptr, address, key);
}

pub inline fn sstore(self: Host, address: Address, key: U256, value: U256) SstoreResult {
    return self.vtable.sstore(self.ptr, address, key, value);
}

pub inline fn tload(self: Host, address: Address, key: U256) U256 {
    return self.vtable.tload(self.ptr, address, key);
}

pub inline fn tstore(self: Host, address: Address, key: U256, value: U256) void {
    self.vtable.tstore(self.ptr, address, key, value);
}
