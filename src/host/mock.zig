//! Mock host implementation for testing.
//!
//! Provides in-memory storage with simple get/set operations.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Host = @import("Host.zig");
const Address = @import("../primitives/mod.zig").Address;
const U256 = @import("../primitives/mod.zig").U256;
const B256 = @import("../primitives/mod.zig").B256;

/// Snapshot of host state for revert functionality.
const Snapshot = struct {
    balances: std.AutoHashMap(Address, U256),
    codes: std.AutoHashMap(Address, []const u8),
    nonces: std.AutoHashMap(Address, u64),

    fn deinit(self: *Snapshot, allocator: Allocator) void {
        // Free all stored code in snapshot
        var code_iter = self.codes.valueIterator();
        while (code_iter.next()) |code| {
            allocator.free(code.*);
        }
        self.codes.deinit();
        self.balances.deinit();
        self.nonces.deinit();
    }
};

/// Simple in-memory host for testing.
pub const MockHost = struct {
    allocator: Allocator,

    /// Account balances
    balances: std.AutoHashMap(Address, U256),

    /// Account code
    codes: std.AutoHashMap(Address, []const u8),

    /// Account nonces
    nonces: std.AutoHashMap(Address, u64),

    /// Snapshots for state revert
    snapshots: std.ArrayList(Snapshot),

    pub fn init(allocator: Allocator) MockHost {
        return .{
            .allocator = allocator,
            .balances = std.AutoHashMap(Address, U256).init(allocator),
            .codes = std.AutoHashMap(Address, []const u8).init(allocator),
            .nonces = std.AutoHashMap(Address, u64).init(allocator),
            .snapshots = std.ArrayList(Snapshot){},
        };
    }

    pub fn deinit(self: *MockHost) void {
        // Free all snapshots
        for (self.snapshots.items) |*snapshot| {
            snapshot.deinit(self.allocator);
        }
        self.snapshots.deinit(self.allocator);

        // Free all stored code
        var code_iter = self.codes.valueIterator();
        while (code_iter.next()) |code| {
            self.allocator.free(code.*);
        }
        self.codes.deinit();
        self.balances.deinit();
        self.nonces.deinit();
    }

    /// Convert to Host interface
    pub fn host(self: *MockHost) Host {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    // Configuration helpers

    pub fn setBalance(self: *MockHost, address: Address, balance: U256) !void {
        try self.balances.put(address, balance);
    }

    pub fn setCode(self: *MockHost, address: Address, code: []const u8) !void {
        // Free old code if it exists
        if (self.codes.get(address)) |old_code| {
            self.allocator.free(old_code);
        }

        // Duplicate code to own it
        const owned_code = try self.allocator.dupe(u8, code);
        try self.codes.put(address, owned_code);
    }

    // Vtable implementation

    const vtable = Host.VTable{
        .balance = balanceImpl,
        .code = codeImpl,
        .codeHash = codeHashImpl,
        .codeSize = codeSizeImpl,
        .blockHash = blockHashImpl,
        .snapshot = snapshotImpl,
        .revertToSnapshot = revertToSnapshotImpl,
        .transfer = transferImpl,
        .nonce = nonceImpl,
        .accountExists = accountExistsImpl,
    };

    fn balanceImpl(ptr: *anyopaque, address: Address) U256 {
        const self: *MockHost = @ptrCast(@alignCast(ptr));
        return self.balances.get(address) orelse U256.ZERO;
    }

    fn codeImpl(ptr: *anyopaque, address: Address) Allocator.Error![]const u8 {
        const self: *MockHost = @ptrCast(@alignCast(ptr));
        if (self.codes.get(address)) |code| {
            // Return copy so caller owns it
            return self.allocator.dupe(u8, code);
        }
        // Return empty slice for non-existent accounts
        return &[_]u8{};
    }

    fn codeHashImpl(ptr: *anyopaque, address: Address) B256 {
        const self: *MockHost = @ptrCast(@alignCast(ptr));
        if (self.codes.get(address)) |code| {
            if (code.len == 0) return B256.zero();
            // Compute actual Keccak256 hash
            var hash: [32]u8 = undefined;
            std.crypto.hash.sha3.Keccak256.hash(code, &hash, .{});
            return B256{ .bytes = hash };
        }
        return B256.zero();
    }

    fn codeSizeImpl(ptr: *anyopaque, address: Address) usize {
        const self: *MockHost = @ptrCast(@alignCast(ptr));
        if (self.codes.get(address)) |code| {
            return code.len;
        }
        return 0;
    }

    fn blockHashImpl(ptr: *anyopaque, block_number: u64) B256 {
        _ = ptr;
        _ = block_number;
        // Mock implementation: return zero for all blocks
        // Real implementation would query historical block hashes
        return B256.zero();
    }

    fn snapshotImpl(ptr: *anyopaque) Allocator.Error!usize {
        const self: *MockHost = @ptrCast(@alignCast(ptr));

        // Preserve the current state
        var snapshot_balances = std.AutoHashMap(Address, U256).init(self.allocator);
        var snapshot_codes = std.AutoHashMap(Address, []const u8).init(self.allocator);
        var snapshot_nonces = std.AutoHashMap(Address, u64).init(self.allocator);

        // Clone balances
        var balance_iter = self.balances.iterator();
        while (balance_iter.next()) |entry| {
            try snapshot_balances.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Clone codes (must duplicate the byte slices)
        var code_iter = self.codes.iterator();
        while (code_iter.next()) |entry| {
            const code_copy = try self.allocator.dupe(u8, entry.value_ptr.*);
            try snapshot_codes.put(entry.key_ptr.*, code_copy);
        }

        // Clone nonces
        var nonce_iter = self.nonces.iterator();
        while (nonce_iter.next()) |entry| {
            try snapshot_nonces.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        const snapshot = Snapshot{
            .balances = snapshot_balances,
            .codes = snapshot_codes,
            .nonces = snapshot_nonces,
        };

        try self.snapshots.append(self.allocator, snapshot);
        // Return snapshot ID (index)
        return self.snapshots.items.len - 1;
    }

    fn revertToSnapshotImpl(ptr: *anyopaque, snapshot_id: usize) void {
        const self: *MockHost = @ptrCast(@alignCast(ptr));

        // Safety check: snapshot_id must be valid
        if (snapshot_id >= self.snapshots.items.len) {
            return; // Invalid snapshot ID, no-op
        }

        // Free current state
        var code_iter = self.codes.valueIterator();
        while (code_iter.next()) |code| {
            self.allocator.free(code.*);
        }
        self.codes.deinit();
        self.balances.deinit();
        self.nonces.deinit();

        // Clone snapshot state to current (snapshot remains, for potential future reverts)
        const snapshot = &self.snapshots.items[snapshot_id];

        self.balances = std.AutoHashMap(Address, U256).init(self.allocator);
        self.codes = std.AutoHashMap(Address, []const u8).init(self.allocator);
        self.nonces = std.AutoHashMap(Address, u64).init(self.allocator);

        // Copy balances from snapshot
        var balance_iter = snapshot.balances.iterator();
        while (balance_iter.next()) |entry| {
            self.balances.put(entry.key_ptr.*, entry.value_ptr.*) catch {
                // Out of memory during revert is unrecoverable
                @panic("Out of memory during revert");
            };
        }

        // Copy codes from snapshot (must duplicate)
        var snapshot_code_iter = snapshot.codes.iterator();
        while (snapshot_code_iter.next()) |entry| {
            const code_copy = self.allocator.dupe(u8, entry.value_ptr.*) catch {
                @panic("Out of memory during revert");
            };
            self.codes.put(entry.key_ptr.*, code_copy) catch {
                @panic("Out of memory during revert");
            };
        }

        // Copy nonces from snapshot
        var nonce_iter = snapshot.nonces.iterator();
        while (nonce_iter.next()) |entry| {
            self.nonces.put(entry.key_ptr.*, entry.value_ptr.*) catch {
                @panic("Out of memory during revert");
            };
        }

        // Discard all snapshots created after this one
        while (self.snapshots.items.len > snapshot_id + 1) {
            // Safe: we check len before calling
            var discarded = self.snapshots.pop().?;
            discarded.deinit(self.allocator);
        }
    }

    fn transferImpl(ptr: *anyopaque, from: Address, to: Address, value: U256) (Allocator.Error || Host.Error)!void {
        const self: *MockHost = @ptrCast(@alignCast(ptr));

        // Zero-value transfers succeed without changes
        if (value.isZero()) {
            return;
        }

        // Get from balance (defaults to 0 if account doesn't exist)
        const from_balance = self.balances.get(from) orelse U256.ZERO;

        // Check sufficient balance
        if (from_balance.lt(value)) {
            return error.InsufficientBalance;
        }

        // Calculate new balances
        const new_from_balance = from_balance.sub(value);
        const to_balance = self.balances.get(to) orelse U256.ZERO;
        const new_to_balance = to_balance.add(value);

        // Update balances
        try self.balances.put(from, new_from_balance);
        try self.balances.put(to, new_to_balance);
    }

    fn nonceImpl(ptr: *anyopaque, address: Address) u64 {
        const self: *MockHost = @ptrCast(@alignCast(ptr));
        return self.nonces.get(address) orelse 0;
    }

    fn accountExistsImpl(ptr: *anyopaque, address: Address) bool {
        const self: *MockHost = @ptrCast(@alignCast(ptr));
        // Account exists if it has balance, code, or nonce
        if (self.balances.contains(address)) return true;
        if (self.codes.contains(address)) return true;
        if (self.nonces.contains(address)) return true;
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

test "Init and deinit" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    // Should start empty
    const h = mock.host();
    const balance = h.balance(Address.zero());
    try expectEqual(U256.ZERO, balance);
}

test "Balance operations" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const addr = Address.fromHex("0x0000000000000000000000000000000000001234") catch unreachable;
    const expected_balance = U256.fromU64(999);

    // Set balance
    try mock.setBalance(addr, expected_balance);

    // Query via host interface
    const h = mock.host();
    const actual_balance = h.balance(addr);

    try expectEqual(expected_balance, actual_balance);
}

test "Code operations" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const addr = Address.fromHex("0x0000000000000000000000000000000000005678") catch unreachable;
    const expected_code = [_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }; // PUSH1 1 PUSH1 2 ADD

    // Set code
    try mock.setCode(addr, &expected_code);

    // Query via host interface
    const h = mock.host();
    const actual_code = try h.code(addr);
    defer std.testing.allocator.free(actual_code);

    try expectEqualSlices(u8, &expected_code, actual_code);
    try expectEqual(expected_code.len, h.codeSize(addr));
}

test "Non-existent account returns defaults" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const h = mock.host();
    const nonexistent = Address.fromHex("0x00000000000000000000000000000000DEADBEEF") catch unreachable;

    // Balance should be zero
    try expectEqual(U256.ZERO, h.balance(nonexistent));

    // Code should be empty
    const code = try h.code(nonexistent);
    defer std.testing.allocator.free(code);
    try expectEqual(0, code.len);

    // Code size should be zero
    try expectEqual(0, h.codeSize(nonexistent));

    // Code hash should be zero
    try expectEqual(B256.zero(), h.codeHash(nonexistent));
}

test "Multiple accounts" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const addr1 = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const addr2 = Address.fromHex("0x0000000000000000000000000000000000002222") catch unreachable;

    try mock.setBalance(addr1, U256.fromU64(100));
    try mock.setBalance(addr2, U256.fromU64(200));

    const code1 = [_]u8{0x60};
    const code2 = [_]u8{ 0x60, 0x01 };
    try mock.setCode(addr1, &code1);
    try mock.setCode(addr2, &code2);

    const h = mock.host();

    // Verify balances are independent
    try expectEqual(U256.fromU64(100), h.balance(addr1));
    try expectEqual(U256.fromU64(200), h.balance(addr2));

    // Verify code is independent
    try expectEqual(1, h.codeSize(addr1));
    try expectEqual(2, h.codeSize(addr2));
}

test "Snapshot and revert - balances" {
    const test_cases = [_]struct {
        initial_balance: u64,
        modified_balance: u64,
        expected_after_revert: u64,
    }{
        // Simple revert.
        .{
            .initial_balance = 100,
            .modified_balance = 200,
            .expected_after_revert = 100,
        },
        // Zero balance.
        .{
            .initial_balance = 0,
            .modified_balance = 500,
            .expected_after_revert = 0,
        },
        // Revert non-zero.
        .{
            .initial_balance = 1000,
            .modified_balance = 0,
            .expected_after_revert = 1000,
        },
    };

    for (test_cases) |tc| {
        var mock = MockHost.init(std.testing.allocator);
        defer mock.deinit();

        const addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;

        // Set initial balance
        try mock.setBalance(addr, U256.fromU64(tc.initial_balance));

        const h = mock.host();

        // Create snapshot
        const snapshot_id = try h.snapshot();
        // First snapshot should be ID 0
        try expectEqual(0, snapshot_id);

        // Modify balance
        try mock.setBalance(addr, U256.fromU64(tc.modified_balance));
        try expectEqual(U256.fromU64(tc.modified_balance), h.balance(addr));

        // Revert
        h.revertToSnapshot(snapshot_id);

        // Verify reverted to initial balance
        try expectEqual(U256.fromU64(tc.expected_after_revert), h.balance(addr));
    }
}

test "Nested snapshots" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const h = mock.host();

    // State 0: balance = 100
    try mock.setBalance(addr, U256.fromU64(100));
    const snap0 = try h.snapshot();

    // State 1: balance = 200
    try mock.setBalance(addr, U256.fromU64(200));
    const snap1 = try h.snapshot();

    // State 2: balance = 300
    try mock.setBalance(addr, U256.fromU64(300));
    try expectEqual(U256.fromU64(300), h.balance(addr));

    // Revert to snap1 (balance should be 200)
    h.revertToSnapshot(snap1);
    try expectEqual(U256.fromU64(200), h.balance(addr));

    // Revert to snap0 (balance should be 100)
    h.revertToSnapshot(snap0);
    try expectEqual(U256.fromU64(100), h.balance(addr));
}

test "Snapshot with code" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const h = mock.host();

    // Set initial code
    const code1 = [_]u8{ 0x60, 0x01 }; // PUSH1 1
    try mock.setCode(addr, &code1);

    // Create snapshot
    const snapshot_id = try h.snapshot();

    // Modify code
    const code2 = [_]u8{ 0x60, 0x02, 0x60, 0x03 }; // PUSH1 2 PUSH1 3
    try mock.setCode(addr, &code2);
    try expectEqual(4, h.codeSize(addr));

    // Revert
    h.revertToSnapshot(snapshot_id);

    // Verify code reverted
    try expectEqual(2, h.codeSize(addr));
    const reverted_code = try h.code(addr);
    defer std.testing.allocator.free(reverted_code);
    try expectEqualSlices(u8, &code1, reverted_code);
}

test "Multiple snapshots work independently" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const h = mock.host();

    // Create 3 snapshots with different balances
    try mock.setBalance(addr, U256.fromU64(100));
    const snap0 = try h.snapshot();

    try mock.setBalance(addr, U256.fromU64(200));
    const snap1 = try h.snapshot();

    try mock.setBalance(addr, U256.fromU64(300));
    const snap2 = try h.snapshot();

    // Verify snapshot IDs are unique
    try expectEqual(0, snap0);
    try expectEqual(1, snap1);
    try expectEqual(2, snap2);

    // Revert to middle snapshot
    h.revertToSnapshot(snap1);
    try expectEqual(U256.fromU64(200), h.balance(addr));

    // Later snapshot should be discarded
    try expectEqual(2, mock.snapshots.items.len); // snap0, snap1 remain
}

test "Transfer: basic value transfer" {
    const test_cases = [_]struct {
        from_initial: u64,
        to_initial: u64,
        transfer_amount: u64,
        should_succeed: bool,
        from_final: u64,
        to_final: u64,
    }{
        // Successful transfer
        .{
            .from_initial = 100,
            .to_initial = 50,
            .transfer_amount = 30,
            .should_succeed = true,
            .from_final = 70,
            .to_final = 80,
        },
        // Insufficient balance
        .{
            .from_initial = 100,
            .to_initial = 50,
            .transfer_amount = 101,
            .should_succeed = false,
            .from_final = 100,
            .to_final = 50,
        },
        // Zero-value transfer
        .{
            .from_initial = 100,
            .to_initial = 0,
            .transfer_amount = 0,
            .should_succeed = true,
            .from_final = 100,
            .to_final = 0,
        },
        // Transfer entire balance
        .{
            .from_initial = 100,
            .to_initial = 0,
            .transfer_amount = 100,
            .should_succeed = true,
            .from_final = 0,
            .to_final = 100,
        },
    };

    for (test_cases) |tc| {
        var mock = MockHost.init(std.testing.allocator);
        defer mock.deinit();

        const from_addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
        const to_addr = Address.fromHex("0x0000000000000000000000000000000000002222") catch unreachable;

        // Set initial balances
        try mock.setBalance(from_addr, U256.fromU64(tc.from_initial));
        try mock.setBalance(to_addr, U256.fromU64(tc.to_initial));

        const h = mock.host();

        // Attempt transfer
        if (tc.should_succeed) {
            try h.transfer(from_addr, to_addr, U256.fromU64(tc.transfer_amount));
        } else {
            const result = h.transfer(from_addr, to_addr, U256.fromU64(tc.transfer_amount));
            try std.testing.expectError(error.InsufficientBalance, result);
        }

        // Verify final balances
        try expectEqual(U256.fromU64(tc.from_final), h.balance(from_addr));
        try expectEqual(U256.fromU64(tc.to_final), h.balance(to_addr));
    }
}

test "Transfer: to non-existent account creates account" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const from_addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const to_addr = Address.fromHex("0x0000000000000000000000000000000000002222") catch unreachable;

    // Set up sender with balance
    try mock.setBalance(from_addr, U256.fromU64(100));

    const h = mock.host();

    // Verify recipient doesn't exist (balance is 0)
    try expectEqual(U256.ZERO, h.balance(to_addr));

    // Transfer to non-existent account
    try h.transfer(from_addr, to_addr, U256.fromU64(30));

    // Verify balances
    try expectEqual(U256.fromU64(70), h.balance(from_addr));
    try expectEqual(U256.fromU64(30), h.balance(to_addr));
}

test "Transfer: from non-existent account fails" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const from_addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const to_addr = Address.fromHex("0x0000000000000000000000000000000000002222") catch unreachable;

    // Don't set any balance for from_addr (defaults to 0)
    try mock.setBalance(to_addr, U256.fromU64(50));

    const h = mock.host();

    // Attempt transfer from non-existent account
    const result = h.transfer(from_addr, to_addr, U256.fromU64(1));
    try std.testing.expectError(error.InsufficientBalance, result);

    // Verify balances unchanged
    try expectEqual(U256.ZERO, h.balance(from_addr));
    try expectEqual(U256.fromU64(50), h.balance(to_addr));
}

test "Nonce: default and set operations" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const h = mock.host();

    // Non-existent account returns nonce 0
    try expectEqual(0, h.nonce(addr));

    // Set nonce via direct map access (no helper method needed for tests)
    try mock.nonces.put(addr, 42);
    try expectEqual(42, h.nonce(addr));

    // Update nonce
    try mock.nonces.put(addr, 100);
    try expectEqual(100, h.nonce(addr));
}

test "Nonce: snapshot and revert" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const h = mock.host();

    // Set initial nonce
    try mock.nonces.put(addr, 5);
    try expectEqual(5, h.nonce(addr));

    // Create snapshot
    const snapshot_id = try h.snapshot();

    // Modify nonce
    try mock.nonces.put(addr, 10);
    try expectEqual(10, h.nonce(addr));

    // Revert to snapshot
    h.revertToSnapshot(snapshot_id);

    // Verify nonce reverted
    try expectEqual(5, h.nonce(addr));
}

test "AccountExists: various account states" {
    var mock = MockHost.init(std.testing.allocator);
    defer mock.deinit();

    const addr_balance = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const addr_code = Address.fromHex("0x0000000000000000000000000000000000002222") catch unreachable;
    const addr_nonce = Address.fromHex("0x0000000000000000000000000000000000003333") catch unreachable;
    const addr_none = Address.fromHex("0x0000000000000000000000000000000000004444") catch unreachable;

    const h = mock.host();

    // Account with only balance
    try mock.setBalance(addr_balance, U256.fromU64(100));
    try std.testing.expect(h.accountExists(addr_balance));

    // Account with only code
    const code = [_]u8{ 0x60, 0x01 };
    try mock.setCode(addr_code, &code);
    try std.testing.expect(h.accountExists(addr_code));

    // Account with only nonce
    try mock.nonces.put(addr_nonce, 1);
    try std.testing.expect(h.accountExists(addr_nonce));

    // Account with nothing
    try std.testing.expect(!h.accountExists(addr_none));
}
