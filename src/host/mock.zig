//! Mock host implementation for testing.
//!
//! Provides in-memory storage with simple get/set operations.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Host = @import("Host.zig");
const Address = @import("../primitives/mod.zig").Address;
const U256 = @import("../primitives/mod.zig").U256;
const B256 = @import("../primitives/mod.zig").B256;

/// Simple in-memory host for testing.
pub const MockHost = struct {
    allocator: Allocator,

    /// Account balances
    balances: std.AutoHashMap(Address, U256),

    /// Account code
    codes: std.AutoHashMap(Address, []const u8),

    pub fn init(allocator: Allocator) MockHost {
        return .{
            .allocator = allocator,
            .balances = std.AutoHashMap(Address, U256).init(allocator),
            .codes = std.AutoHashMap(Address, []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *MockHost) void {
        // Free all stored code
        var code_iter = self.codes.valueIterator();
        while (code_iter.next()) |code| {
            self.allocator.free(code.*);
        }
        self.codes.deinit();
        self.balances.deinit();
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
