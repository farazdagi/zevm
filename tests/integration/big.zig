const std = @import("std");
const zevm = @import("zevm");
const U256 = zevm.primitives.U256;

const testing = std.testing;
const Managed = std.math.big.int.Managed;

// ============================================================================
// Helper Functions
// ============================================================================

/// Convert U256 to Managed bigint by building up from limbs
fn managedFromU256(allocator: std.mem.Allocator, value: U256) !Managed {
    var result = try Managed.init(allocator);
    errdefer result.deinit();

    // Start with zero
    try result.set(0);

    // Build up the value one limb at a time
    // Process from most significant to least significant
    for (0..4) |i| {
        const idx = 3 - i; // Start from limb[3]
        const limb = value.limbs[idx];

        if (i > 0 or limb != 0) {
            // Shift left by 64 bits (multiply by 2^64)
            if (i > 0) {
                var shift_val = try Managed.initSet(allocator, 1);
                defer shift_val.deinit();
                try shift_val.shiftLeft(&shift_val, 64);
                try result.mul(&result, &shift_val);
            }

            // Add the current limb
            if (limb != 0) {
                var limb_val = try Managed.initSet(allocator, limb);
                defer limb_val.deinit();
                try result.add(&result, &limb_val);
            }
        }
    }

    return result;
}

/// Convert Managed bigint to U256 by converting through bytes
/// Assumes the managed value fits in 256 bits (will be masked)
fn u256FromManaged(value: Managed) U256 {
    // Convert to bytes and back
    var bytes: [32]u8 = [_]u8{0} ** 32;
    value.toConst().writeTwosComplement(bytes[0..], .big);

    return U256.fromBeBytes(&bytes);
}

/// Mask a Managed value to 256 bits (simulate U256 wrapping)
fn managedMask256(allocator: std.mem.Allocator, value: Managed) !Managed {
    // Create 2^256 as a managed int
    var modulus = try Managed.init(allocator);
    errdefer modulus.deinit();

    // Set modulus to 2^256 (shift 1 left by 256 bits)
    try modulus.set(1);
    try modulus.shiftLeft(&modulus, 256);

    // Take value mod 2^256
    var result = try Managed.init(allocator);
    errdefer result.deinit();

    var q = try Managed.init(allocator);
    defer q.deinit();

    try Managed.divTrunc(&q, &result, &value, &modulus);

    modulus.deinit();
    return result;
}

/// Compare U256 with Managed (after masking Managed to 256 bits)
fn expectU256EqlManaged(u256_val: U256, managed: Managed) !void {
    const u256_from_managed = u256FromManaged(managed);

    try testing.expect(u256_val.eql(u256_from_managed));
}

// ============================================================================
// Conversion Tests
// ============================================================================

test "U256 vs Managed: conversion round-trip zero" {
    const allocator = testing.allocator;

    const u256_zero = U256.ZERO;
    var managed = try managedFromU256(allocator, u256_zero);
    defer managed.deinit();

    const u256_back = u256FromManaged(managed);
    try testing.expect(u256_back.eql(U256.ZERO));
}

test "U256 vs Managed: conversion round-trip one" {
    const allocator = testing.allocator;

    const u256_one = U256.ONE;
    var managed = try managedFromU256(allocator, u256_one);
    defer managed.deinit();

    const u256_back = u256FromManaged(managed);
    try testing.expect(u256_back.eql(U256.ONE));
}

test "U256 vs Managed: conversion round-trip max" {
    const allocator = testing.allocator;

    const u256_max = U256.MAX;
    var managed = try managedFromU256(allocator, u256_max);
    defer managed.deinit();

    const u256_back = u256FromManaged(managed);
    try testing.expect(u256_back.eql(U256.MAX));
}

test "U256 vs Managed: conversion round-trip u64 value" {
    const allocator = testing.allocator;

    const u256_val = U256.fromU64(0xDEADBEEFCAFEBABE);
    var managed = try managedFromU256(allocator, u256_val);
    defer managed.deinit();

    const u256_back = u256FromManaged(managed);
    try testing.expect(u256_back.eql(u256_val));
}

// ============================================================================
// Arithmetic Operation Tests
// ============================================================================

test "U256 vs Managed: addition simple" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(12345);
    const b_u256 = U256.fromU64(67890);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    // Perform addition on both
    const result_u256 = a_u256.add(b_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.add(&a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: addition with carry" {
    const allocator = testing.allocator;

    const a_u256 = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0, 0, 0 } };
    const b_u256 = U256.fromU64(1);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.add(b_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.add(&a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: addition with overflow (wrapping)" {
    const allocator = testing.allocator;

    const a_u256 = U256.MAX;
    const b_u256 = U256.ONE;

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    // U256 wraps to zero
    const result_u256 = a_u256.add(b_u256);

    // Managed doesn't overflow, so we need to mask it
    var result_managed_full = try Managed.init(allocator);
    defer result_managed_full.deinit();
    try result_managed_full.add(&a_managed, &b_managed);

    var result_managed = try managedMask256(allocator, result_managed_full);
    defer result_managed.deinit();

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: subtraction simple" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(67890);
    const b_u256 = U256.fromU64(12345);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.sub(b_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.sub(&a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: subtraction with borrow" {
    const allocator = testing.allocator;

    const a_u256 = U256{ .limbs = .{ 0, 1, 0, 0 } }; // 2^64
    const b_u256 = U256.fromU64(1);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.sub(b_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.sub(&a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: subtraction with underflow (wrapping)" {
    const allocator = testing.allocator;

    const a_u256 = U256.ZERO;
    const b_u256 = U256.ONE;

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    // U256 wraps to MAX
    const result_u256 = a_u256.sub(b_u256);

    // Managed goes negative, need to mask
    var result_managed_full = try Managed.init(allocator);
    defer result_managed_full.deinit();
    try result_managed_full.sub(&a_managed, &b_managed);

    var result_managed = try managedMask256(allocator, result_managed_full);
    defer result_managed.deinit();

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: multiplication simple" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(12345);
    const b_u256 = U256.fromU64(67890);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.mul(b_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.mul(&a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: multiplication large values" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(0xFFFFFFFFFFFFFFFF);
    const b_u256 = U256.fromU64(2);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.mul(b_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.mul(&a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: multiplication with overflow" {
    const allocator = testing.allocator;

    const a_u256 = U256.MAX;
    const b_u256 = U256.fromU64(2);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.mul(b_u256);

    var result_managed_full = try Managed.init(allocator);
    defer result_managed_full.deinit();
    try result_managed_full.mul(&a_managed, &b_managed);

    var result_managed = try managedMask256(allocator, result_managed_full);
    defer result_managed.deinit();

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: division simple" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(67890);
    const b_u256 = U256.fromU64(123);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.div(b_u256);

    var q_managed = try Managed.init(allocator);
    defer q_managed.deinit();
    var r_managed = try Managed.init(allocator);
    defer r_managed.deinit();
    try Managed.divTrunc(&q_managed, &r_managed, &a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, q_managed);
}

test "U256 vs Managed: division by zero returns zero" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(12345);
    const b_u256 = U256.ZERO;

    // U256 returns zero for division by zero (EVM spec)
    const result_u256 = a_u256.div(b_u256);
    try testing.expect(result_u256.eql(U256.ZERO));

    // Managed would panic/error, so we just verify U256 behavior
    _ = allocator;
}

test "U256 vs Managed: remainder simple" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(67890);
    const b_u256 = U256.fromU64(123);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.rem(b_u256);

    var q_managed = try Managed.init(allocator);
    defer q_managed.deinit();
    var r_managed = try Managed.init(allocator);
    defer r_managed.deinit();
    try Managed.divTrunc(&q_managed, &r_managed, &a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, r_managed);
}

// ============================================================================
// Bitwise Operation Tests
// ============================================================================

test "U256 vs Managed: bitwise AND" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(0b1111_0000_1010_1010);
    const b_u256 = U256.fromU64(0b1010_1010_1111_0000);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.bitAnd(b_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.bitAnd(&a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: bitwise OR" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(0b1111_0000_0000_0000);
    const b_u256 = U256.fromU64(0b0000_1010_1010_1010);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.bitOr(b_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.bitOr(&a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: bitwise XOR" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(0b1111_0000_1010_1010);
    const b_u256 = U256.fromU64(0b1010_1010_1111_0000);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    const result_u256 = a_u256.bitXor(b_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.bitXor(&a_managed, &b_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: bitwise NOT" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(0xFF00FF00FF00FF00);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();

    const result_u256 = a_u256.bitNot();

    // For NOT, Managed doesn't have a direct operation
    // We need to XOR with MAX to simulate NOT in 256 bits
    var max_managed = try managedFromU256(allocator, U256.MAX);
    defer max_managed.deinit();

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.bitXor(&a_managed, &max_managed);

    try expectU256EqlManaged(result_u256, result_managed);
}

// ============================================================================
// Shift Operation Tests
// ============================================================================

test "U256 vs Managed: left shift small" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(0xFF);
    const shift: u32 = 8;

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();

    const result_u256 = a_u256.shl(shift);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.shiftLeft(&a_managed, shift);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: left shift across limb boundary" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(0xFFFFFFFFFFFFFFFF);
    const shift: u32 = 64;

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();

    const result_u256 = a_u256.shl(shift);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.shiftLeft(&a_managed, shift);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: left shift with overflow" {
    const allocator = testing.allocator;

    const a_u256 = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    const shift: u32 = 8;

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();

    const result_u256 = a_u256.shl(shift);

    var result_managed_full = try Managed.init(allocator);
    defer result_managed_full.deinit();
    try result_managed_full.shiftLeft(&a_managed, shift);

    var result_managed = try managedMask256(allocator, result_managed_full);
    defer result_managed.deinit();

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: right shift small" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(0xFF00);
    const shift: u32 = 8;

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();

    const result_u256 = a_u256.shr(shift);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.shiftRight(&a_managed, shift);

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: right shift across limb boundary" {
    const allocator = testing.allocator;

    const a_u256 = U256{ .limbs = .{ 0, 0xFFFFFFFFFFFFFFFF, 0, 0 } };
    const shift: u32 = 64;

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();

    const result_u256 = a_u256.shr(shift);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.shiftRight(&a_managed, shift);

    try expectU256EqlManaged(result_u256, result_managed);
}

// ============================================================================
// Comparison Operation Tests
// ============================================================================

test "U256 vs Managed: equality comparison" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(12345);
    const b_u256 = U256.fromU64(12345);
    const c_u256 = U256.fromU64(67890);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();
    var c_managed = try managedFromU256(allocator, c_u256);
    defer c_managed.deinit();

    try testing.expect(a_u256.eql(b_u256) == (a_managed.order(b_managed) == .eq));
    try testing.expect(a_u256.eql(c_u256) == (a_managed.order(c_managed) == .eq));
}

test "U256 vs Managed: less than comparison" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(12345);
    const b_u256 = U256.fromU64(67890);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    try testing.expect(a_u256.lt(b_u256) == (a_managed.order(b_managed) == .lt));
    try testing.expect(b_u256.lt(a_u256) == (b_managed.order(a_managed) == .lt));
}

test "U256 vs Managed: greater than comparison" {
    const allocator = testing.allocator;

    const a_u256 = U256.fromU64(67890);
    const b_u256 = U256.fromU64(12345);

    var a_managed = try managedFromU256(allocator, a_u256);
    defer a_managed.deinit();
    var b_managed = try managedFromU256(allocator, b_u256);
    defer b_managed.deinit();

    try testing.expect(a_u256.gt(b_u256) == (a_managed.order(b_managed) == .gt));
    try testing.expect(b_u256.gt(a_u256) == (b_managed.order(a_managed) == .gt));
}

// ============================================================================
// Special Operation Tests
// ============================================================================

test "U256 vs Managed: exponentiation small" {
    const allocator = testing.allocator;

    const base_u256 = U256.fromU64(2);
    const exp_u256 = U256.fromU64(8);

    var base_managed = try managedFromU256(allocator, base_u256);
    defer base_managed.deinit();
    var exp_managed = try managedFromU256(allocator, exp_u256);
    defer exp_managed.deinit();

    const result_u256 = base_u256.exp(exp_u256);

    var result_managed = try Managed.init(allocator);
    defer result_managed.deinit();
    try result_managed.pow(&base_managed, @intCast(exp_u256.toU64().?));

    try expectU256EqlManaged(result_u256, result_managed);
}

test "U256 vs Managed: exponentiation with wrapping" {
    const allocator = testing.allocator;

    const base_u256 = U256.fromU64(2);
    const exp_u256 = U256.fromU64(256);

    var base_managed = try managedFromU256(allocator, base_u256);
    defer base_managed.deinit();
    var exp_managed = try managedFromU256(allocator, exp_u256);
    defer exp_managed.deinit();

    const result_u256 = base_u256.exp(exp_u256);

    var result_managed_full = try Managed.init(allocator);
    defer result_managed_full.deinit();
    try result_managed_full.pow(&base_managed, @intCast(exp_u256.toU64().?));

    var result_managed = try managedMask256(allocator, result_managed_full);
    defer result_managed.deinit();

    try expectU256EqlManaged(result_u256, result_managed);
}
