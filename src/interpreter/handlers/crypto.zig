//! Crypto instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Address = @import("../../primitives/address.zig").Address;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Compute Keccak-256 hash (KECCAK256).
///
/// Stack: [offset, size, ...] -> [hash, ...]
/// Reads data from memory and replaces stack operands with the keccak256 hash.
/// Gas is charged in interpreter before calling this function.
pub fn opKeccak256(interp: *Interpreter) !void {
    const offset_u256 = try interp.ctx.stack.pop();
    const size_ptr = try interp.ctx.stack.peekMut(0);

    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const size = size_ptr.toUsize() orelse return error.InvalidOffset;

    // Ensure memory is expanded (gas already charged by dynamic gas function)
    try interp.ctx.memory.ensureCapacity(offset, size);

    // Read data from memory
    const data = try interp.ctx.memory.getSlice(offset, size);

    // Compute Keccak-256 hash
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(data, &hash, .{});

    // Convert hash to U256 and write in-place
    size_ptr.* = U256.fromBeBytes(&hash);
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Spec = @import("../../hardfork.zig").Spec;
const Env = @import("../../context.zig").Env;
const MockHost = @import("../../host/mock.zig").MockHost;
const CallContext = @import("../interpreter.zig").CallContext;
const Evm = @import("../../evm.zig").Evm;
const constants = @import("../../constants.zig");

test "opKeccak256: empty string" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.CANCUN);
    const bytecode = &[_]u8{0x00}; // STOP
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero(), Address.zero(), U256.ZERO);
    var interp = Interpreter.init(allocator, ctx, evm.interpreterConfig(1000000, evm.is_static));
    defer interp.deinit();

    // Push size=0, offset=0 (stack will be [offset, size] with offset on top)
    try interp.ctx.stack.push(U256.fromU64(0)); // size (pushed first, will be second)
    try interp.ctx.stack.push(U256.fromU64(0)); // offset (pushed second, will be on top)

    // Execute KECCAK256
    try opKeccak256(&interp);

    // Verify result matches EMPTY_KECCAK256 constant
    const result = try interp.ctx.stack.pop();
    const result_bytes = result.toBeBytes();
    try expectEqualSlices(u8, &constants.EMPTY_KECCAK256, &result_bytes);
}

test "opKeccak256: known value" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.CANCUN);
    const bytecode = &[_]u8{0x00}; // STOP
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero(), Address.zero(), U256.ZERO);
    var interp = Interpreter.init(allocator, ctx, evm.interpreterConfig(1000000, evm.is_static));
    defer interp.deinit();

    // Store test data in memory: "hello"
    const test_data = "hello";
    for (test_data, 0..) |byte, i| {
        try interp.ctx.memory.mstore8(i, byte);
    }

    // Push size=5, offset=0 (stack will be [offset, size] with offset on top)
    try interp.ctx.stack.push(U256.fromU64(5)); // size (pushed first, will be second)
    try interp.ctx.stack.push(U256.fromU64(0)); // offset (pushed second, will be on top)

    // Execute KECCAK256
    try opKeccak256(&interp);

    // Verify result
    const result = try interp.ctx.stack.pop();

    // Expected hash of "hello"
    // keccak256("hello") = 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8
    var expected_hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(test_data, &expected_hash, .{});
    const expected = U256.fromBeBytes(&expected_hash);

    try expectEqual(expected, result);
}

test "opKeccak256: 32-byte input" {
    const allocator = std.testing.allocator;
    const spec = Spec.forFork(.CANCUN);
    const bytecode = &[_]u8{0x00}; // STOP
    const env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const ctx = try CallContext.init(allocator, try allocator.dupe(u8, bytecode), Address.zero(), Address.zero(), U256.ZERO);
    var interp = Interpreter.init(allocator, ctx, evm.interpreterConfig(1000000, evm.is_static));
    defer interp.deinit();

    // Store 32 bytes of test data
    const test_data = [_]u8{0xFF} ** 32;
    for (test_data, 0..) |byte, i| {
        try interp.ctx.memory.mstore8(i, byte);
    }

    // Push size=32, offset=0 (stack will be [offset, size] with offset on top)
    try interp.ctx.stack.push(U256.fromU64(32)); // size (pushed first, will be second)
    try interp.ctx.stack.push(U256.fromU64(0)); // offset (pushed second, will be on top)

    // Execute KECCAK256
    try opKeccak256(&interp);

    // Verify result
    const result = try interp.ctx.stack.pop();

    // Compute expected hash
    var expected_hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(&test_data, &expected_hash, .{});
    const expected = U256.fromBeBytes(&expected_hash);

    try expectEqual(expected, result);
}
