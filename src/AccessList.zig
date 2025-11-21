//! Access list for EIP-2929 cold/warm state access tracking.
//!
//! First access is "cold" (higher gas cost), subsequent accesses are "warm" (lower gas cost).
//! Provides the `Accessor` interface (vtable pattern) for decoupled access to the list's functionality.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Address = @import("primitives/address.zig").Address;
const U256 = @import("primitives/big.zig").U256;
const Env = @import("context.zig").Env;
const Spec = @import("hardfork.zig").Spec;

const AccessList = @This();

allocator: Allocator,

/// Set of addresses that have been accessed (warm).
///
/// The `accessed_addresses: Set[Address]` from the specs.
addresses: std.AutoHashMap(Address, void),

/// Map of address -> set of storage slots that have been accessed.
///
/// The `accessed_storage_keys: Set[Tuple[Address, Bytes32]]` from the spec.
storage_keys: std.AutoHashMap(Address, std.AutoHashMap(U256, void)),

/// Initialize an empty access list.
pub fn init(allocator: Allocator) AccessList {
    return .{
        .allocator = allocator,
        .addresses = std.AutoHashMap(Address, void).init(allocator),
        .storage_keys = std.AutoHashMap(Address, std.AutoHashMap(U256, void)).init(allocator),
    };
}

/// Initialize access list with transaction-level preparation.
pub fn initForTransaction(allocator: Allocator, env: *const Env, spec: Spec) AccessList {
    var list = init(allocator);

    // Pre-warm access list.
    {
        // Pre-warm sender address (EIP-2929).
        // The sender is always accessed during transaction execution.
        _ = list.warmAddress(env.tx.caller) catch {};

        // Pre-warm transaction recipient (EIP-2929).
        // For CALL: warm the target contract address.
        // For CREATE: will be handled when CREATE is executed (address computed then).
        if (env.tx.to) |recipient| {
            _ = list.warmAddress(recipient) catch {};
        }

        // Pre-warm COINBASE for Shanghai+ (EIP-3651).
        if (spec.fork.isAtLeast(.SHANGHAI)) {
            _ = list.warmAddress(env.block.coinbase) catch {};
        }

        // Pre-warm precompile addresses (0x01 through 0x09).
        // EIP-2929: Precompiles are considered warm from transaction start.
        for (1..10) |i| {
            var addr_bytes: [20]u8 = [_]u8{0} ** 20;
            addr_bytes[19] = @intCast(i);
            _ = list.warmAddress(Address.init(addr_bytes)) catch {};
        }
    }

    return list;
}

/// Free all memory used by the access list.
pub fn deinit(self: *AccessList) void {
    // Free all nested storage key maps.
    var it = self.storage_keys.valueIterator();
    while (it.next()) |slot_map| {
        slot_map.deinit();
    }
    self.storage_keys.deinit();
    self.addresses.deinit();
}

/// Mark an address as warm.
///
/// Returns true if it was cold (first access).
pub fn warmAddress(self: *AccessList, address: Address) Allocator.Error!bool {
    const result = try self.addresses.getOrPut(address);
    return !result.found_existing;
}

/// Mark a storage slot as warm.
///
/// Also warms the address.
/// Returns true if the slot was cold (first access).
pub fn warmSlot(self: *AccessList, address: Address, key: U256) Allocator.Error!bool {
    // Always warm the address as well.
    _ = try self.warmAddress(address);

    // Get or create the slot map for this address.
    const slot_map_result = try self.storage_keys.getOrPut(address);
    if (!slot_map_result.found_existing) {
        slot_map_result.value_ptr.* = std.AutoHashMap(U256, void).init(self.allocator);
    }

    // Check if slot is cold.
    const slot_result = try slot_map_result.value_ptr.getOrPut(key);
    return !slot_result.found_existing;
}

/// Check if an address is warm.
pub fn isAddressWarm(self: *const AccessList, address: Address) bool {
    return self.addresses.contains(address);
}

/// Check if a storage slot is warm.
pub fn isSlotWarm(self: *const AccessList, address: Address, key: U256) bool {
    const slot_map = self.storage_keys.get(address) orelse return false;
    return slot_map.contains(key);
}

/// Create an Accessor interface for this access list.
///
/// Returns an Accessor that provides vtable-based access to this list's warming functions.
pub fn accessor(self: *AccessList) Accessor {
    const Impl = struct {
        fn warmAddress(ptr: *anyopaque, address: Address) bool {
            const list: *AccessList = @ptrCast(@alignCast(ptr));
            return list.warmAddress(address) catch unreachable;
        }
        fn warmSlot(ptr: *anyopaque, address: Address, slot: U256) bool {
            const list: *AccessList = @ptrCast(@alignCast(ptr));
            return list.warmSlot(address, slot) catch unreachable;
        }
    };

    return .{
        .ptr = self,
        .vtable = &.{
            .warmAddress = Impl.warmAddress,
            .warmSlot = Impl.warmSlot,
        },
    };
}

/// Create a deep copy of this access list for snapshots.
pub fn clone(self: *const AccessList, allocator: Allocator) Allocator.Error!AccessList {
    var new_list = AccessList{
        .allocator = allocator,
        .addresses = std.AutoHashMap(Address, void).init(allocator),
        .storage_keys = std.AutoHashMap(Address, std.AutoHashMap(U256, void)).init(allocator),
    };

    // Copy addresses.
    var addr_it = self.addresses.keyIterator();
    while (addr_it.next()) |addr| {
        try new_list.addresses.put(addr.*, {});
    }

    // Copy storage keys (deep copy nested maps).
    var storage_it = self.storage_keys.iterator();
    while (storage_it.next()) |entry| {
        var new_slot_map = std.AutoHashMap(U256, void).init(allocator);
        var slot_it = entry.value_ptr.keyIterator();
        while (slot_it.next()) |slot| {
            try new_slot_map.put(slot.*, {});
        }
        try new_list.storage_keys.put(entry.key_ptr.*, new_slot_map);
    }

    return new_list;
}

/// Interface for access list operations.
///
/// Use via re-export: `@import("zevm").AccessListAccessor`, so that there's no, even visual,
/// coupling between the `Interpreter` and `AccessList` struct.
pub const Accessor = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        warmAddress: *const fn (ptr: *anyopaque, address: Address) bool,
        warmSlot: *const fn (ptr: *anyopaque, address: Address, slot: U256) bool,
    };

    /// Warm an address and return whether it was cold.
    ///
    /// If the address was not previously accessed (cold), marks it as warm and returns true.
    /// If already warm, returns false.
    ///
    /// Expected usage:
    ///
    /// ```zig
    /// const is_cold = accessor.warmAddress(address);
    /// ```
    /// Then, depending on whether the access was cold/warm, charge different amount of gas.
    pub inline fn warmAddress(self: Accessor, address: Address) bool {
        return self.vtable.warmAddress(self.ptr, address);
    }

    /// Warm a storage slot and return whether it was cold.
    ///
    /// If the slot was not previously accessed (cold), marks both the slot and address as warm
    /// and returns true. If already warm, returns false.
    pub inline fn warmSlot(self: Accessor, address: Address, slot: U256) bool {
        return self.vtable.warmSlot(self.ptr, address, slot);
    }

    /// Create a no-op accessor for pre-Berlin forks.
    ///
    /// Returns an accessor where everything is considered "cold".
    ///
    /// This is used when access lists don't exist (pre-Berlin), so the dynamic gas functions
    /// can work uniformly across all forks.
    pub fn alwaysCold() Accessor {
        const S = struct {
            fn warmAddress(_: *anyopaque, _: Address) bool {
                return true; // Always cold.
            }
            fn warmSlot(_: *anyopaque, _: Address, _: U256) bool {
                return true; // Always cold.
            }
        };

        return .{
            .ptr = undefined,
            .vtable = &.{
                .warmAddress = S.warmAddress,
                .warmSlot = S.warmSlot,
            },
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "AccessList: warmAddress returns cold then warm" {
    var list = AccessList.init(std.testing.allocator);
    defer list.deinit();

    const addr = Address.init([_]u8{0x42} ** 20);

    // First access is cold.
    const first = try list.warmAddress(addr);
    try expect(first);

    // Second access is warm.
    const second = try list.warmAddress(addr);
    try expect(!second);

    // Third access is still warm.
    const third = try list.warmAddress(addr);
    try expect(!third);
}

test "AccessList: warmSlot warms address implicitly" {
    var list = AccessList.init(std.testing.allocator);
    defer list.deinit();

    const addr = Address.init([_]u8{0x42} ** 20);
    const slot = U256.fromU64(100);

    // Warm the slot (should also warm address).
    const slot_cold = try list.warmSlot(addr, slot);
    try expect(slot_cold);

    // Address should now be warm.
    try expect(list.isAddressWarm(addr));

    // Slot should now be warm.
    try expect(list.isSlotWarm(addr, slot));

    // Warming address again should return warm.
    const addr_warm = try list.warmAddress(addr);
    try expect(!addr_warm);
}

test "AccessList: clone creates independent copy" {
    var original = AccessList.init(std.testing.allocator);
    defer original.deinit();

    const addr1 = Address.init([_]u8{0x01} ** 20);
    const addr2 = Address.init([_]u8{0x02} ** 20);
    const slot = U256.fromU64(42);

    // Warm some addresses and slots in original.
    _ = try original.warmAddress(addr1);
    _ = try original.warmSlot(addr1, slot);

    // Clone.
    var cloned = try original.clone(std.testing.allocator);
    defer cloned.deinit();

    // Cloned should have same state.
    try expect(cloned.isAddressWarm(addr1));
    try expect(cloned.isSlotWarm(addr1, slot));
    try expect(!cloned.isAddressWarm(addr2));

    // Modify original - add addr2.
    _ = try original.warmAddress(addr2);

    // Cloned should NOT have addr2 (independent).
    try expect(original.isAddressWarm(addr2));
    try expect(!cloned.isAddressWarm(addr2));

    // Modify cloned - add different slot.
    const slot2 = U256.fromU64(99);
    _ = try cloned.warmSlot(addr1, slot2);

    // Original should NOT have slot2.
    try expect(!original.isSlotWarm(addr1, slot2));
    try expect(cloned.isSlotWarm(addr1, slot2));
}

test "AccessList: multiple addresses and slots" {
    var list = AccessList.init(std.testing.allocator);
    defer list.deinit();

    // Create multiple addresses.
    var addresses: [10]Address = undefined;
    for (0..10) |i| {
        var bytes: [20]u8 = undefined;
        @memset(&bytes, @as(u8, @intCast(i)));
        addresses[i] = Address.init(bytes);
    }

    // Warm all addresses.
    for (addresses) |addr| {
        const is_cold = try list.warmAddress(addr);
        try expect(is_cold);
    }

    // All should be warm now.
    for (addresses) |addr| {
        try expect(list.isAddressWarm(addr));
        const is_cold = try list.warmAddress(addr);
        try expect(!is_cold);
    }

    // Add multiple slots to first address.
    for (0..100) |i| {
        const slot = U256.fromU64(i);
        const is_cold = try list.warmSlot(addresses[0], slot);
        try expect(is_cold);
    }

    // All slots should be warm.
    for (0..100) |i| {
        const slot = U256.fromU64(i);
        try expect(list.isSlotWarm(addresses[0], slot));
    }
}

test "AccessList: zero address tracking" {
    var list = AccessList.init(std.testing.allocator);
    defer list.deinit();

    const zero_addr = Address.init([_]u8{0} ** 20);

    // Zero address should work like any other.
    const first = try list.warmAddress(zero_addr);
    try expect(first);

    const second = try list.warmAddress(zero_addr);
    try expect(!second);

    try expect(list.isAddressWarm(zero_addr));
}

test "AccessList: max U256 storage key" {
    var list = AccessList.init(std.testing.allocator);
    defer list.deinit();

    const addr = Address.init([_]u8{0x42} ** 20);
    const max_slot = U256.MAX;
    const zero_slot = U256.ZERO;

    // Test max slot.
    const max_cold = try list.warmSlot(addr, max_slot);
    try expect(max_cold);

    const max_warm = try list.warmSlot(addr, max_slot);
    try expect(!max_warm);

    // Zero slot should still be cold.
    const zero_cold = try list.warmSlot(addr, zero_slot);
    try expect(zero_cold);

    try expect(list.isSlotWarm(addr, max_slot));
    try expect(list.isSlotWarm(addr, zero_slot));
}

test "AccessList: different slots same address" {
    var list = AccessList.init(std.testing.allocator);
    defer list.deinit();

    const addr = Address.init([_]u8{0x42} ** 20);
    const slot1 = U256.fromU64(1);
    const slot2 = U256.fromU64(2);

    // Warm slot1.
    const slot1_cold = try list.warmSlot(addr, slot1);
    try expect(slot1_cold);

    // Slot2 should still be cold.
    const slot2_cold = try list.warmSlot(addr, slot2);
    try expect(slot2_cold);

    // Both should be warm now.
    try expect(list.isSlotWarm(addr, slot1));
    try expect(list.isSlotWarm(addr, slot2));
}

test "AccessList: same slot different addresses" {
    var list = AccessList.init(std.testing.allocator);
    defer list.deinit();

    const addr1 = Address.init([_]u8{0x01} ** 20);
    const addr2 = Address.init([_]u8{0x02} ** 20);
    const slot = U256.fromU64(42);

    // Warm slot for addr1.
    const cold1 = try list.warmSlot(addr1, slot);
    try expect(cold1);

    // Same slot for addr2 should still be cold.
    const cold2 = try list.warmSlot(addr2, slot);
    try expect(cold2);

    // Both should be warm.
    try expect(list.isSlotWarm(addr1, slot));
    try expect(list.isSlotWarm(addr2, slot));
}

test "AccessList.Accessor: alwaysCold returns true for all addresses" {
    const acc = AccessList.Accessor.alwaysCold();

    const addr1 = Address.init([_]u8{0x01} ** 20);
    const addr2 = Address.init([_]u8{0x02} ** 20);

    // All addresses should be cold.
    try expect(acc.warmAddress(addr1));
    try expect(acc.warmAddress(addr2));

    // Even the same address again is cold (no state tracking).
    try expect(acc.warmAddress(addr1));
}

test "AccessList.Accessor: alwaysCold returns true for all slots" {
    const acc = AccessList.Accessor.alwaysCold();

    const addr = Address.init([_]u8{0x42} ** 20);
    const slot1 = U256.fromU64(1);
    const slot2 = U256.fromU64(2);

    // All slots should be cold.
    try expect(acc.warmSlot(addr, slot1));
    try expect(acc.warmSlot(addr, slot2));

    // Same slot again is cold.
    try expect(acc.warmSlot(addr, slot1));
}

test "AccessList.Accessor: vtable dispatch works correctly" {
    // Create a simple implementation that tracks state.
    const TestImpl = struct {
        warm_count: usize = 0,

        fn warmAddr(ptr: *anyopaque, _: Address) bool {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.warm_count += 1;
            return self.warm_count == 1; // First call is cold.
        }

        fn warmSlotFn(ptr: *anyopaque, _: Address, _: U256) bool {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.warm_count += 1;
            return self.warm_count == 1; // First call is cold.
        }
    };

    var impl = TestImpl{};
    const acc = AccessList.Accessor{
        .ptr = &impl,
        .vtable = &.{
            .warmAddress = TestImpl.warmAddr,
            .warmSlot = TestImpl.warmSlotFn,
        },
    };

    const addr = Address.init([_]u8{0x42} ** 20);

    // First call is cold.
    try expect(acc.warmAddress(addr));
    try expect(impl.warm_count == 1);

    // Second call is warm.
    try expect(!acc.warmAddress(addr));
    try expect(impl.warm_count == 2);
}
