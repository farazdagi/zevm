const std = @import("std");

/// 256-bit unsigned integer optimized for EVM operations.
///
/// Internal representation uses four u64 limbs in little-endian order:
/// - limbs[0]: least significant 64 bits
/// - limbs[3]: most significant 64 bits
///
/// All arithmetic operations wrap on overflow (modulo 2^256), matching EVM semantics.
pub const U256 = struct {
    limbs: [4]u64,

    const Self = @This();

    pub const ZERO = Self{ .limbs = .{ 0, 0, 0, 0 } };
    pub const ONE = Self{ .limbs = .{ 1, 0, 0, 0 } };
    pub const MAX = Self{ .limbs = .{
        0xFFFFFFFFFFFFFFFF,
        0xFFFFFFFFFFFFFFFF,
        0xFFFFFFFFFFFFFFFF,
        0xFFFFFFFFFFFFFFFF,
    } };

    /// Create a U256 from a u64 value.
    pub inline fn fromU64(value: u64) Self {
        return Self{ .limbs = .{ value, 0, 0, 0 } };
    }

    /// Create a U256 from a u128 value.
    pub inline fn fromU128(value: u128) Self {
        return Self{
            .limbs = .{
                @as(u64, @truncate(value)),
                @as(u64, @truncate(value >> 64)),
                0,
                0,
            },
        };
    }

    /// Create a U256 from a boolean value (0 or 1).
    pub inline fn fromBool(value: bool) Self {
        return Self{ .limbs = .{ @intFromBool(value), 0, 0, 0 } };
    }

    /// Create a U256 from little-endian bytes (32 bytes).
    ///
    /// The first byte is the least significant.
    pub inline fn fromLeBytes(bytes: *const [32]u8) Self {
        var limbs: [4]u64 = undefined;
        for (0..4) |i| {
            const offset = i * 8;
            limbs[i] = std.mem.readInt(u64, bytes[offset..][0..8], .little);
        }
        return Self{ .limbs = limbs };
    }

    /// Create a U256 from big-endian bytes (32 bytes).
    ///
    /// This is the standard format for EVM (most significant byte first).
    pub inline fn fromBeBytes(bytes: *const [32]u8) Self {
        var limbs: [4]u64 = undefined;
        // Read in reverse order for big-endian
        for (0..4) |i| {
            const offset = (3 - i) * 8;
            limbs[i] = std.mem.readInt(u64, bytes[offset..][0..8], .big);
        }
        return Self{ .limbs = limbs };
    }

    /// Create a U256 from big-endian bytes, left-padding with zeros if needed.
    ///
    /// This is used for EVM PUSH operations where immediate values are 1-32 bytes.
    /// If the slice is longer than 32 bytes, only the rightmost bytes are used.
    /// If shorter, it's left-padded with zeros (EVM semantics).
    ///
    /// Example:
    /// - [0x12, 0x34] becomes 0x0000...001234 (30 zero bytes, then 0x12, 0x34)
    /// - [0x12, ...32 more bytes] takes rightmost 32 bytes
    pub inline fn fromBeBytesPadded(value: []const u8) Self {
        var padded: [32]u8 = [_]u8{0} ** 32;

        if (value.len >= 32) {
            // Take rightmost 32 bytes
            @memcpy(&padded, value[value.len - 32 ..]);
        } else {
            // Left-pad with zeros
            @memcpy(padded[32 - value.len ..], value);
        }

        return Self.fromBeBytes(&padded);
    }

    /// Convert to u64 if the value fits, otherwise return null.
    pub inline fn toU64(self: Self) ?u64 {
        if (self.limbs[1] != 0 or self.limbs[2] != 0 or self.limbs[3] != 0) {
            return null;
        }
        return self.limbs[0];
    }

    /// Convert to u128 if the value fits, otherwise return null.
    pub inline fn toU128(self: Self) ?u128 {
        if (self.limbs[2] != 0 or self.limbs[3] != 0) {
            return null;
        }
        return (@as(u128, self.limbs[1]) << 64) | @as(u128, self.limbs[0]);
    }

    /// Convert to usize if the value fits, otherwise return null.
    pub inline fn toUsize(self: Self) ?usize {
        const val_u64 = self.toU64() orelse return null;
        // Cast u64 to usize. On 64-bit systems this is a no-op.
        // On 32-bit systems, returns null if value doesn't fit in 32 bits.
        return std.math.cast(usize, val_u64);
    }

    /// Write the U256 as little-endian bytes (32 bytes).
    pub inline fn toLeBytes(self: Self) [32]u8 {
        var bytes: [32]u8 = undefined;
        for (0..4) |i| {
            const offset = i * 8;
            std.mem.writeInt(u64, bytes[offset..][0..8], self.limbs[i], .little);
        }
        return bytes;
    }

    /// Write the U256 as big-endian bytes (32 bytes).
    ///
    /// This is the standard format for EVM.
    pub inline fn toBeBytes(self: Self) [32]u8 {
        var bytes: [32]u8 = undefined;
        for (0..4) |i| {
            const offset = (3 - i) * 8;
            std.mem.writeInt(u64, bytes[offset..][0..8], self.limbs[i], .big);
        }
        return bytes;
    }

    /// Generic set method supporting multiple types as a zero-cost abstraction.
    pub inline fn set(self: *Self, value: anytype) void {
        const T = @TypeOf(value);

        // Use compile-time type checks for zero-cost abstraction.
        if (T == bool) {
            self.* = fromBool(value);
        } else if (T == U256) {
            self.* = value;
        } else if (@typeInfo(T) == .comptime_int) {
            if (value < 0) {
                @compileError("Negative comptime_int values not supported in set()");
            }
            if (value <= std.math.maxInt(u64)) {
                self.* = fromU64(@intCast(value));
            } else if (value <= std.math.maxInt(u128)) {
                self.* = fromU128(@intCast(value));
            } else {
                @compileError("comptime_int value too large for set() (max: u128)");
            }
        } else if (@typeInfo(T) == .int) {
            const int_info = @typeInfo(T).int;
            if (int_info.signedness == .unsigned) {
                if (int_info.bits <= 64) {
                    self.* = fromU64(@intCast(value));
                } else if (int_info.bits <= 128) {
                    self.* = fromU128(@intCast(value));
                } else {
                    @compileError("Unsupported integer bit width for set(): " ++ @typeName(T));
                }
            } else {
                @compileError("Signed integers not supported in set(): " ++ @typeName(T));
            }
        } else {
            @compileError("Unsupported type for set(): " ++ @typeName(T));
        }
    }

    /// Check if the value is zero.
    pub inline fn isZero(self: Self) bool {
        return self.limbs[0] == 0 and self.limbs[1] == 0 and self.limbs[2] == 0 and self.limbs[3] == 0;
    }

    /// Returns the number of bits required to represent this number.
    ///
    /// Returns 0 for zero.
    pub inline fn bitLen(self: Self) u32 {
        // Find the most significant non-zero limb
        for (0..4) |i| {
            const idx = 3 - i;
            if (self.limbs[idx] != 0) {
                // Count leading zeros in this limb
                const leading_zeros = @clz(self.limbs[idx]);
                return @as(u32, @intCast(idx * 64 + 64 - leading_zeros));
            }
        }
        return 0;
    }

    /// Returns the minimum number of bytes required to represent this number.
    ///
    /// Returns 0 for zero.
    pub inline fn byteLen(self: Self) u32 {
        const bits = self.bitLen();
        return (bits + 7) / 8;
    }

    /// Check if the value fits in a u64.
    pub inline fn fitsInU64(self: Self) bool {
        return self.limbs[1] == 0 and self.limbs[2] == 0 and self.limbs[3] == 0;
    }

    /// Check if the value fits in a u128.
    pub inline fn fitsInU128(self: Self) bool {
        return self.limbs[2] == 0 and self.limbs[3] == 0;
    }

    /// Compare equality (EVM: EQ).
    pub inline fn eql(self: Self, other: Self) bool {
        return self.limbs[0] == other.limbs[0] and
            self.limbs[1] == other.limbs[1] and
            self.limbs[2] == other.limbs[2] and
            self.limbs[3] == other.limbs[3];
    }

    /// Less than comparison (EVM: LT).
    ///
    /// Returns true if self < other (unsigned comparison).
    pub inline fn lt(self: Self, other: Self) bool {
        // Compare from most significant to least significant
        if (self.limbs[3] != other.limbs[3]) return self.limbs[3] < other.limbs[3];
        if (self.limbs[2] != other.limbs[2]) return self.limbs[2] < other.limbs[2];
        if (self.limbs[1] != other.limbs[1]) return self.limbs[1] < other.limbs[1];
        return self.limbs[0] < other.limbs[0];
    }

    /// Greater than comparison (EVM: GT).
    ///
    /// Returns true if self > other (unsigned comparison).
    pub inline fn gt(self: Self, other: Self) bool {
        // Compare from most significant to least significant
        if (self.limbs[3] != other.limbs[3]) return self.limbs[3] > other.limbs[3];
        if (self.limbs[2] != other.limbs[2]) return self.limbs[2] > other.limbs[2];
        if (self.limbs[1] != other.limbs[1]) return self.limbs[1] > other.limbs[1];
        return self.limbs[0] > other.limbs[0];
    }

    /// Less than or equal comparison.
    pub inline fn lte(self: Self, other: Self) bool {
        return !self.gt(other);
    }

    /// Greater than or equal comparison.
    pub inline fn gte(self: Self, other: Self) bool {
        return !self.lt(other);
    }

    /// Signed less than comparison (EVM: SLT).
    ///
    /// Interprets the values as two's complement signed integers.
    pub inline fn slt(self: Self, other: Self) bool {
        const self_sign = self.limbs[3] >> 63; // MSB of most significant limb
        const other_sign = other.limbs[3] >> 63;

        // If signs differ, negative is less than positive
        if (self_sign != other_sign) {
            return self_sign > other_sign; // 1 (negative) < 0 (positive)
        }

        // Same sign: compare as unsigned
        return self.lt(other);
    }

    /// Signed greater than comparison (EVM: SGT).
    ///
    /// Interprets the values as two's complement signed integers.
    pub inline fn sgt(self: Self, other: Self) bool {
        const self_sign = self.limbs[3] >> 63;
        const other_sign = other.limbs[3] >> 63;

        // If signs differ, positive is greater than negative
        if (self_sign != other_sign) {
            return self_sign < other_sign; // 0 (positive) > 1 (negative)
        }

        // Same sign: compare as unsigned
        return self.gt(other);
    }

    /// Bitwise AND (EVM: AND).
    pub inline fn bitAnd(self: Self, other: Self) Self {
        return Self{
            .limbs = .{
                self.limbs[0] & other.limbs[0],
                self.limbs[1] & other.limbs[1],
                self.limbs[2] & other.limbs[2],
                self.limbs[3] & other.limbs[3],
            },
        };
    }

    /// Bitwise OR (EVM: OR).
    pub inline fn bitOr(self: Self, other: Self) Self {
        return Self{
            .limbs = .{
                self.limbs[0] | other.limbs[0],
                self.limbs[1] | other.limbs[1],
                self.limbs[2] | other.limbs[2],
                self.limbs[3] | other.limbs[3],
            },
        };
    }

    /// Bitwise XOR (EVM: XOR).
    pub inline fn bitXor(self: Self, other: Self) Self {
        return Self{
            .limbs = .{
                self.limbs[0] ^ other.limbs[0],
                self.limbs[1] ^ other.limbs[1],
                self.limbs[2] ^ other.limbs[2],
                self.limbs[3] ^ other.limbs[3],
            },
        };
    }

    /// Bitwise NOT (EVM: NOT).
    pub inline fn bitNot(self: Self) Self {
        return Self{
            .limbs = .{
                ~self.limbs[0],
                ~self.limbs[1],
                ~self.limbs[2],
                ~self.limbs[3],
            },
        };
    }

    /// Extract the nth byte (EVM: BYTE).
    ///
    /// Index 0 is the most significant byte.
    /// Returns 0 if index >= 32.
    pub inline fn byte(self: Self, index: u8) u8 {
        if (index >= 32) return 0;

        // Convert to big-endian bytes to match EVM semantics
        const bytes = self.toBeBytes();
        return bytes[index];
    }

    /// Left shift (EVM: SHL).
    ///
    /// Shifts the value left by `shift` bits.
    /// If shift >= 256, returns zero.
    pub inline fn shl(self: Self, shift: u32) Self {
        if (shift >= 256) return Self.ZERO;
        if (shift == 0) return self;

        const limb_shift = shift / 64; // How many full limbs to shift
        const bit_shift = shift % 64; // Remaining bits to shift within limbs

        var result = Self.ZERO;

        if (bit_shift == 0) {
            // Limb-aligned shift
            var i: usize = limb_shift;
            while (i < 4) : (i += 1) {
                result.limbs[i] = self.limbs[i - limb_shift];
            }
        } else {
            // Need to shift bits across limb boundaries
            var i: usize = limb_shift;
            while (i < 4) : (i += 1) {
                const src_idx = i - limb_shift;
                result.limbs[i] = self.limbs[src_idx] << @intCast(bit_shift);

                // Carry bits from the next lower limb
                if (src_idx > 0) {
                    result.limbs[i] |= self.limbs[src_idx - 1] >> @intCast(64 - bit_shift);
                }
            }
        }

        return result;
    }

    /// Logical right shift (EVM: SHR).
    ///
    /// Shifts the value right by `shift` bits, filling with zeros.
    /// If shift >= 256, returns zero.
    pub inline fn shr(self: Self, shift: u32) Self {
        if (shift >= 256) return Self.ZERO;
        if (shift == 0) return self;

        const limb_shift = shift / 64;
        const bit_shift = shift % 64;

        var result = Self.ZERO;

        if (bit_shift == 0) {
            // Simple limb-aligned shift
            var i: usize = 0;
            while (i < 4 - limb_shift) : (i += 1) {
                result.limbs[i] = self.limbs[i + limb_shift];
            }
        } else {
            // Need to shift bits across limb boundaries
            var i: usize = 0;
            while (i < 4 - limb_shift) : (i += 1) {
                const src_idx = i + limb_shift;
                result.limbs[i] = self.limbs[src_idx] >> @intCast(bit_shift);

                // Carry bits from the next higher limb
                if (src_idx < 3) {
                    result.limbs[i] |= self.limbs[src_idx + 1] << @intCast(64 - bit_shift);
                }
            }
        }

        return result;
    }

    /// Arithmetic right shift (EVM: SAR).
    ///
    /// Shifts right, preserving the sign bit (MSB).
    /// If shift >= 256, returns all 1s if negative, all 0s if positive.
    pub inline fn sar(self: Self, shift: u32) Self {
        const sign_bit = (self.limbs[3] >> 63) & 1;
        const is_negative = sign_bit == 1;

        if (shift >= 256) {
            return if (is_negative) Self.MAX else Self.ZERO;
        }

        if (shift == 0) return self;

        // Perform logical right shift
        var result = self.shr(shift);

        // Fill in the high bits with the sign bit
        if (is_negative) {
            const limb_shift = shift / 64;
            const bit_shift = shift % 64;

            // Fill complete high limbs
            var i: usize = 3;
            while (i >= 4 - limb_shift and i < 4) : (i -= 1) {
                result.limbs[i] = 0xFFFFFFFFFFFFFFFF;
                if (i == 0) break;
            }

            // Fill partial bits in the highest affected limb
            if (limb_shift < 4 and bit_shift > 0) {
                const high_limb_idx = 3 - limb_shift;
                const mask = @as(u64, 0xFFFFFFFFFFFFFFFF) << @intCast(64 - bit_shift);
                result.limbs[high_limb_idx] |= mask;
            }
        }

        return result;
    }

    /// Sign extend from byte position (EVM: SIGNEXTEND).
    ///
    /// Extends the sign bit from byte position `b` to fill all higher bytes.
    /// Byte 0 is the least significant byte.
    pub inline fn signExtend(self: Self, byte_pos: u8) Self {
        if (byte_pos >= 31) return self; // No extension needed for byte 31

        // Get the sign bit from the specified byte position
        const limb_index = byte_pos / 8;
        const byte_in_limb = byte_pos % 8;

        const byte_val = @as(u8, @truncate((self.limbs[limb_index] >> @intCast(byte_in_limb * 8)) & 0xFF));
        const sign_bit = (byte_val >> 7) & 1;

        // Update either by clearing or setting sign bits.
        var result = self;

        // Update within the same limb
        // When bits_to_keep == 0 (byte_in_limb == 7), entire limb is kept as-is
        const bits_to_keep = ((byte_in_limb + 1) * 8) % 64;
        if (bits_to_keep > 0) {
            if (sign_bit == 0) {
                // Clear higher bits in the same limb
                const mask = (@as(u64, 1) << @intCast(bits_to_keep)) -% 1;
                result.limbs[limb_index] &= mask;
            } else {
                // Set higher bits in the same limb
                const mask = ~((@as(u64, 1) << @intCast(bits_to_keep)) -% 1);
                result.limbs[limb_index] |= mask;
            }
        }

        // Update all higher limbs
        var i = limb_index + 1;
        while (i < 4) : (i += 1) {
            // Positive: clear all higher bits
            // Negative: set all higher bits
            result.limbs[i] = if (sign_bit == 0) @as(u64, 0) else 0xFFFFFFFFFFFFFFFF;
        }

        return result;
    }

    /// Addition with wrapping overflow (EVM: ADD).
    ///
    /// Computes (self + other) mod 2^256.
    pub inline fn add(self: Self, other: Self) Self {
        // Result location mechanism should avoid real allocation to stack, but we can also
        // resort to in-place assignment by overwriting self, say U256.add(&a, a.*, b).
        // Note: when checked really similar ASM code is generated in both cases.
        var result: Self = undefined;
        var carry: u64 = 0;

        // Add limb by limb from LSB to MSB, propagating carry
        inline for (0..4) |i| {
            // Use @addWithOverflow to detect carry
            const sum1 = @addWithOverflow(self.limbs[i], other.limbs[i]);
            const sum2 = @addWithOverflow(sum1[0], carry);

            result.limbs[i] = sum2[0];

            // Carry is 1 if either addition overflowed
            carry = sum1[1] | sum2[1];
        }

        // Final carry is discarded (wrapping behavior)
        return result;
    }

    /// Subtraction with wrapping underflow (EVM: SUB).
    ///
    /// Computes (self - other) mod 2^256.
    pub inline fn sub(self: Self, other: Self) Self {
        var result: Self = undefined;
        var borrow: u64 = 0;

        // Subtract limb by limb from LSB to MSB, propagating borrow
        inline for (0..4) |i| {
            // Use @subWithOverflow to detect borrow
            const diff1 = @subWithOverflow(self.limbs[i], other.limbs[i]);
            const diff2 = @subWithOverflow(diff1[0], borrow);

            result.limbs[i] = diff2[0];

            // Borrow is 1 if either subtraction underflowed
            borrow = diff1[1] | diff2[1];
        }

        // Final borrow is discarded (wrapping behavior)
        return result;
    }

    /// Checked addition that detects overflow.
    ///
    /// Returns null if the operation would overflow.
    pub inline fn checkedAdd(self: Self, other: Self) ?Self {
        var result: Self = undefined;
        var carry: u64 = 0;

        inline for (0..4) |i| {
            const sum1 = @addWithOverflow(self.limbs[i], other.limbs[i]);
            const sum2 = @addWithOverflow(sum1[0], carry);

            result.limbs[i] = sum2[0];
            carry = sum1[1] | sum2[1];
        }

        // If there's a final carry, we overflowed
        return if (carry != 0) null else result;
    }

    /// Checked subtraction that detects underflow.
    ///
    /// Returns null if the operation would underflow (self < other).
    pub inline fn checkedSub(self: Self, other: Self) ?Self {
        var result: Self = undefined;
        var borrow: u64 = 0;

        inline for (0..4) |i| {
            const diff1 = @subWithOverflow(self.limbs[i], other.limbs[i]);
            const diff2 = @subWithOverflow(diff1[0], borrow);

            result.limbs[i] = diff2[0];
            borrow = diff1[1] | diff2[1];
        }

        // If there's a final borrow, we underflowed
        return if (borrow != 0) null else result;
    }

    /// Multiplication with wrapping overflow (EVM: MUL).
    ///
    /// Computes (self * other) mod 2^256.
    pub inline fn mul(self: Self, other: Self) Self {
        // Cache limbs in local variables for better register allocation
        const self_limbs = self.limbs;
        const other_limbs = other.limbs;

        // Multiply each limb of self by each limb of other
        var result = Self.ZERO;

        for (0..4) |i| {
            if (self_limbs[i] == 0) continue;

            var carry: u64 = 0;

            for (0..4) |j| {
                const k = i + j;
                if (k >= 4) break; // Result would overflow into higher limbs (wrapping)

                // Multiply two u64s to get u128 result
                const product = @as(u128, self_limbs[i]) * @as(u128, other_limbs[j]);
                const low = @as(u64, @truncate(product));
                const high = @as(u64, @truncate(product >> 64));

                // Add to existing result limb with carry
                const sum1 = @addWithOverflow(result.limbs[k], low);
                const sum2 = @addWithOverflow(sum1[0], carry);

                result.limbs[k] = sum2[0];

                // Update carry for next iteration
                carry = high + sum1[1] + sum2[1];
            }

            // The remaining carry will be discarded (wrapping)
        }

        return result;
    }

    /// Unsigned division (EVM: DIV).
    ///
    /// Returns self / other, or 0 if other is zero (per EVM spec).
    pub inline fn div(self: Self, other: Self) Self {
        if (self.isZero() or other.isZero() or self.lt(other)) return Self.ZERO;
        if (self.eql(other)) return Self.ONE;
        if (other.eql(Self.ONE)) return self;

        // Fast path for single-limb divisors
        if (other.fitsInU64()) {
            return self.divRemU64(other.limbs[0])[0];
        }

        // Long division algorithm for multi-limb division
        return self.divRem(other)[0];
    }

    /// Unsigned modulo (EVM: MOD).
    ///
    /// Returns self % other, or 0 if other is zero (per EVM spec).
    pub inline fn rem(self: Self, other: Self) Self {
        if (self.isZero() or other.isZero() or self.eql(other) or other.eql(Self.ONE)) return Self.ZERO;
        if (self.lt(other)) return self;

        // Fast path for single-limb divisors
        if (other.fitsInU64()) {
            return self.divRemU64(other.limbs[0])[1];
        }

        // Long division algorithm
        return self.divRem(other)[1];
    }

    /// Signed division (EVM: SDIV).
    ///
    /// Interprets values as two's complement signed integers.
    /// Returns 0 if divisor is zero.
    /// Special case: MIN_I256 / -1 returns MIN_I256 (overflow wraps).
    pub inline fn sdiv(self: Self, other: Self) Self {
        if (other.isZero()) return Self.ZERO;

        const self_negative = (self.limbs[3] >> 63) == 1;
        const other_negative = (other.limbs[3] >> 63) == 1;

        // Special case: MIN_I256 / -1 overflows in two's complement
        // MIN_I256 = 0x8000...0000 (most significant bit set)
        // -1 = 0xFFFF...FFFF (all bits set)
        // The result would be 2^255 which doesn't fit, so it wraps to MIN_I256
        const MIN_I256 = Self{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } };
        if (self.eql(MIN_I256) and other.eql(Self.MAX)) {
            return MIN_I256;
        }

        // Get absolute values
        const self_abs = if (self_negative) self.twosComplement() else self;
        const other_abs = if (other_negative) other.twosComplement() else other;

        // Perform unsigned division
        const quot = self_abs.div(other_abs);

        // Negate result if signs differ (result is negative)
        return if (self_negative != other_negative) quot.twosComplement() else quot;
    }

    /// Signed modulo (EVM: SMOD).
    ///
    /// Result has the same sign as the dividend (self).
    /// Special case: MIN_I256 % -1 returns 0.
    pub inline fn srem(self: Self, other: Self) Self {
        if (other.isZero()) return Self.ZERO;

        // Special case: MIN_I256 % -1 = 0
        // (MIN_I256 / -1 = MIN_I256 with remainder 0)
        const MIN_I256 = Self{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } };
        if (self.eql(MIN_I256) and other.eql(Self.MAX)) {
            return Self.ZERO;
        }

        const self_negative = (self.limbs[3] >> 63) == 1;
        const other_negative = (other.limbs[3] >> 63) == 1;

        const self_abs = if (self_negative) self.twosComplement() else self;
        const other_abs = if (other_negative) other.twosComplement() else other;

        const remainder = self_abs.rem(other_abs);

        // Result has same sign as dividend (self)
        return if (self_negative) remainder.twosComplement() else remainder;
    }

    /// Helper: Two's complement negation.
    fn twosComplement(self: Self) Self {
        return self.bitNot().add(Self.ONE);
    }

    /// Helper: Divide by a u64 divisor (fast path).
    fn divRemU64(self: Self, divisor: u64) [2]Self {
        var quotient = Self.ZERO;
        var remainder: u64 = 0;

        // Divide from most significant limb to least
        for (0..4) |i| {
            const idx = 3 - i;
            const dividend = (@as(u128, remainder) << 64) | self.limbs[idx];
            quotient.limbs[idx] = @as(u64, @truncate(dividend / divisor));
            remainder = @as(u64, @truncate(dividend % divisor));
        }

        return .{ quotient, Self.fromU64(remainder) };
    }

    /// Long division for full U256 divisor.
    ///
    /// Returns [quotient, remainder].
    pub inline fn divRem(self: Self, other: Self) [2]Self {
        var quotient = Self.ZERO;
        var remainder = self;

        // Find the bit position of the most significant bit in divisor
        const divisor_bits = other.bitLen();
        if (divisor_bits == 0) return .{ Self.ZERO, Self.ZERO };

        // Binary long division
        var i: u32 = 256;
        while (i > 0) {
            i -= 1;

            // Shift quotient left
            quotient = quotient.shl(1);

            // Shift remainder left and bring down next bit
            remainder = remainder.shl(1);

            // If remainder >= divisor, subtract and set quotient bit
            if (remainder.gte(other)) {
                remainder = remainder.sub(other);
                quotient = quotient.bitOr(Self.ONE);
            }

            // Optimization: can stop early if remainder is small
            if (remainder.bitLen() < divisor_bits) {
                // Shift quotient by remaining iterations
                if (i > 0) {
                    quotient = quotient.shl(i);
                }
                break;
            }
        }

        return .{ quotient, remainder };
    }

    /// Modular addition (EVM: ADDMOD).
    ///
    /// Computes (self + other) mod modulus.
    /// Returns 0 if modulus is zero.
    pub inline fn addmod(self: Self, other: Self, modulus: Self) Self {
        if (modulus.isZero() or modulus.eql(Self.ONE)) return Self.ZERO;

        // For addmod, we need to handle potential overflow in (a + b)
        // Use checkedAdd, and if it overflows, compute the wrapped result
        if (self.checkedAdd(other)) |sum| {
            return sum.rem(modulus);
        } else {
            // Overflow occurred - reduce operands first
            const a_mod = self.rem(modulus);
            const b_mod = other.rem(modulus);

            if (a_mod.checkedAdd(b_mod)) |sum| {
                return sum.rem(modulus);
            } else {
                // Still overflowed, subtract modulus
                return a_mod.add(b_mod).sub(modulus);
            }
        }
    }

    /// Modular multiplication (EVM: MULMOD).
    ///
    /// Computes (self * other) mod modulus.
    /// Returns 0 if modulus is zero.
    pub inline fn mulmod(self: Self, other: Self, modulus: Self) Self {
        if (self.isZero() or other.isZero()) return Self.ZERO;
        if (modulus.isZero() or modulus.eql(Self.ONE)) return Self.ZERO;

        // For small values that won't overflow, use simple approach
        const self_bits = self.bitLen();
        const other_bits = other.bitLen();

        if (self_bits + other_bits <= 256) {
            // No overflow possible
            return self.mul(other).rem(modulus);
        }

        // For potentially overflowing multiplication, use repeated addition
        // This is slower but correct for mulmod
        var result = Self.ZERO;
        var base = self.rem(modulus);
        var multiplier = other;

        while (!multiplier.isZero()) {
            // If multiplier is odd, add base to result
            if ((multiplier.limbs[0] & 1) == 1) {
                result = result.addmod(base, modulus);
            }

            // Double base, halve multiplier
            base = base.addmod(base, modulus);
            multiplier = multiplier.shr(1);
        }

        return result;
    }

    /// Exponentiation (EVM: EXP).
    ///
    /// Computes self^exponent mod 2^256 (with wrapping).
    pub inline fn exp(self: Self, exponent: Self) Self {
        if (self.eql(Self.ONE) or exponent.isZero()) return Self.ONE;
        if (self.isZero()) return Self.ZERO;
        if (exponent.eql(Self.ONE)) return self;

        // Square-and-multiply algorithm
        var result = Self.ONE;
        var base = self;
        var exp_val = exponent;

        while (!exp_val.isZero()) {
            // If exponent is odd, multiply result by base
            if ((exp_val.limbs[0] & 1) == 1) {
                result = result.mul(base);
            }

            // Square the base, halve the exponent
            base = base.mul(base);
            exp_val = exp_val.shr(1);
        }

        return result;
    }

    /// Format the U256 as a hexadecimal string (0x-prefixed).
    pub fn format(
        self: Self,
        writer: anytype,
    ) !void {
        // Find the most significant non-zero limb
        var start_limb: usize = 4;
        while (start_limb > 0 and self.limbs[start_limb - 1] == 0) {
            start_limb -= 1;
        }

        if (start_limb == 0) {
            try writer.writeAll("0x0");
            return;
        }

        try writer.writeAll("0x");

        // Write most significant limb without leading zeros
        try writer.print("{x}", .{self.limbs[start_limb - 1]});

        // Write remaining limbs with leading zeros (16 hex digits per limb)
        if (start_limb > 1) {
            var i = start_limb - 1;
            while (i > 0) {
                i -= 1;
                try writer.print("{x:0>16}", .{self.limbs[i]});
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;

test "U256: constants" {
    try expect(U256.ZERO.isZero());
    try expect(!U256.ONE.isZero());
    try expectEqual(1, U256.ONE.limbs[0]);
    try expectEqual(0xFFFFFFFFFFFFFFFF, U256.MAX.limbs[0]);
    try expectEqual(0xFFFFFFFFFFFFFFFF, U256.MAX.limbs[3]);
}

test "U256: fromU64" {
    const a = U256.fromU64(42);
    try expectEqual(42, a.limbs[0]);
    try expectEqual(0, a.limbs[1]);
    try expectEqual(0, a.limbs[2]);
    try expectEqual(0, a.limbs[3]);

    const max_u64 = U256.fromU64(0xFFFFFFFFFFFFFFFF);
    try expectEqual(0xFFFFFFFFFFFFFFFF, max_u64.limbs[0]);
    try expect(max_u64.fitsInU64());
}

test "U256: fromU128" {
    const a = U256.fromU128(0x0123456789ABCDEF0123456789ABCDEF);
    try expectEqual(0x0123456789ABCDEF, a.limbs[0]);
    try expectEqual(0x0123456789ABCDEF, a.limbs[1]);
    try expectEqual(0, a.limbs[2]);
    try expectEqual(0, a.limbs[3]);
    try expect(a.fitsInU128());
}

test "U256: fromBool" {
    const true_val = U256.fromBool(true);
    try expect(true_val.eql(U256.ONE));
    try expectEqual(1, true_val.limbs[0]);
    try expectEqual(0, true_val.limbs[1]);

    const false_val = U256.fromBool(false);
    try expect(false_val.eql(U256.ZERO));
    try expect(false_val.isZero());
}

test "U256: set - generic type support" {
    var val: U256 = undefined;

    // Bool values
    {
        val.set(true);
        try expect(val.eql(U256.ONE));

        val.set(false);
        try expect(val.eql(U256.ZERO));
    }

    // Unsigned integers (u8, u16, u32, u64) - test various values for each type
    {
        const test_values = [_]u64{ 0, 1, 42, 255, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF };

        for (test_values) |test_val| {
            // u8
            val.set(@as(u8, @truncate(test_val)));
            try expectEqual(test_val & 0xFF, val.toU64().?);

            // u16
            val.set(@as(u16, @truncate(test_val)));
            try expectEqual(test_val & 0xFFFF, val.toU64().?);

            // u32
            val.set(@as(u32, @truncate(test_val)));
            try expectEqual(test_val & 0xFFFFFFFF, val.toU64().?);

            // u64
            val.set(@as(u64, test_val));
            try expectEqual(test_val, val.toU64().?);
        }
    }

    // u128 values
    {
        const test_u128: u128 = 0x0123456789ABCDEF0123456789ABCDEF;
        val.set(test_u128);
        try expectEqual(test_u128, val.toU128().?);

        const max_u128: u128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        val.set(max_u128);
        try expectEqual(max_u128, val.toU128().?);

        val.set(@as(u128, 42));
        try expectEqual(42, val.toU64().?);
    }

    // U256 values
    {
        val.set(U256.ZERO);
        try expect(val.eql(U256.ZERO));

        val.set(U256.ONE);
        try expect(val.eql(U256.ONE));

        val.set(U256.MAX);
        try expect(val.eql(U256.MAX));

        const custom = U256{ .limbs = .{ 0x1111111111111111, 0x2222222222222222, 0x3333333333333333, 0x4444444444444444 } };
        val.set(custom);
        try expect(val.eql(custom));
    }

    // comptime_int literals
    {
        val.set(0);
        try expect(val.isZero());

        val.set(1);
        try expect(val.eql(U256.ONE));

        val.set(123456789);
        try expectEqual(123456789, val.toU64().?);
    }
}

test "U256: toU64" {
    const a = U256.fromU64(123);
    try expectEqual(123, a.toU64().?);

    const b = U256.fromU128(0x10000000000000000);
    try expect(b.toU64() == null);
}

test "U256: toU128" {
    const a = U256.fromU128(0x123456789ABCDEF0);
    try expectEqual(0x123456789ABCDEF0, a.toU128().?);

    const b = U256{ .limbs = .{ 0, 0, 1, 0 } };
    try expect(b.toU128() == null);
}

test "U256: toUsize" {
    // Test values that fit in usize
    const test_cases = [_]struct {
        input: u64,
        should_fit: bool,
    }{
        .{ .input = 0, .should_fit = true },
        .{ .input = 123, .should_fit = true },
        // Max u32
        .{ .input = 0xFFFFFFFF, .should_fit = true },
        // Max u64, fits only on 64-bit
        .{ .input = 0xFFFFFFFFFFFFFFFF, .should_fit = @sizeOf(usize) == 8 },
    };

    for (test_cases) |tc| {
        const val = U256.fromU64(tc.input);
        const result = val.toUsize();

        if (tc.should_fit) {
            try expect(result != null);
            try expectEqual(tc.input, result.?);
        } else {
            try expect(result == null);
        }
    }

    // Test value that doesn't fit in u64 (and therefore not in usize)
    const big = U256{ .limbs = .{ 0, 1, 0, 0 } }; // 2^64
    try expect(big.toUsize() == null);
}

test "U256: fromBeBytes and toBeBytes" {

    // Test with a known value
    const bytes = [_]u8{
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x00,
    };

    const value = U256.fromBeBytes(&bytes);
    const result = value.toBeBytes();

    try expectEqualSlices(u8, &bytes, &result);
}

test "U256: fromBeBytesPadded - various input sizes" {
    const test_cases = [_]struct {
        input: []const u8,
        expected_u64: ?u64,
        should_be_zero: bool,
    }{
        // 1 byte
        .{
            .input = &[_]u8{0x42},
            .expected_u64 = 0x42,
            .should_be_zero = false,
        },
        // 2 bytes
        .{
            .input = &[_]u8{ 0x12, 0x34 },
            .expected_u64 = 0x1234,
            .should_be_zero = false,
        },
        // Max single byte
        .{
            .input = &[_]u8{0xFF},
            .expected_u64 = 0xFF,
            .should_be_zero = false,
        },
        // Empty slice
        .{
            .input = &[_]u8{},
            .expected_u64 = null,
            .should_be_zero = true,
        },
        // All zeros
        .{
            .input = &[_]u8{ 0x00, 0x00, 0x00 },
            .expected_u64 = null,
            .should_be_zero = true,
        },
        // Exactly 32 bytes
        .{
            .input = &[_]u8{
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x23,
            },
            .expected_u64 = 0x123,
            .should_be_zero = false,
        },
    };

    for (test_cases) |tc| {
        const value = U256.fromBeBytesPadded(tc.input);

        if (tc.should_be_zero) {
            try expect(value.isZero());
        } else {
            if (tc.expected_u64) |expected| {
                try expectEqual(expected, value.toU64().?);
            }
        }

        // For 32-byte input, verify round-trip
        if (tc.input.len == 32) {
            const result_bytes = value.toBeBytes();
            try expectEqualSlices(u8, tc.input, &result_bytes);
        }
    }
}

test "U256: fromBeBytesPadded - 16 bytes with padding" {
    const bytes = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10 };
    const value = U256.fromBeBytesPadded(&bytes);

    // First 16 bytes should be zeros (left padding), then our 16 bytes
    const result_bytes = value.toBeBytes();

    // Check first 16 bytes are zero
    for (0..16) |i| {
        try expectEqual(0, result_bytes[i]);
    }

    // Check last 16 bytes match input
    for (0..16) |i| {
        try expectEqual(bytes[i], result_bytes[16 + i]);
    }
}

test "U256: fromBeBytesPadded - truncation (>32 bytes)" {
    // 40 bytes - should take rightmost 32
    const bytes = [_]u8{
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // These 8 bytes should be discarded
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x23,
    };
    const value = U256.fromBeBytesPadded(&bytes);

    // Should only have the rightmost 32 bytes (the 0xFF bytes are discarded)
    const result_bytes = value.toBeBytes();
    try expectEqualSlices(u8, bytes[8..], &result_bytes);
}

test "U256: fromLeBytes and toLeBytes" {
    const bytes = [_]u8{
        0x00, 0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };

    const value = U256.fromLeBytes(&bytes);
    const result = value.toLeBytes();

    try expectEqualSlices(u8, &bytes, &result);
}

test "U256: isZero" {
    try expect(U256.ZERO.isZero());
    try expect(!U256.ONE.isZero());
    try expect(!U256.fromU64(1).isZero());
    try expect(U256.fromU64(0).isZero());
}

test "U256: bitLen" {
    try expectEqual(0, U256.ZERO.bitLen());
    try expectEqual(1, U256.ONE.bitLen());
    try expectEqual(8, U256.fromU64(0xFF).bitLen());
    try expectEqual(64, U256.fromU64(0xFFFFFFFFFFFFFFFF).bitLen());
    try expectEqual(256, U256.MAX.bitLen());

    // Test value with high bit set in limb[2]
    const val = U256{ .limbs = .{ 0, 0, 0x8000000000000000, 0 } };
    try expectEqual(192, val.bitLen());
}

test "U256: byteLen" {
    const test_cases = [_]struct {
        input: u64,
        expected: u32,
    }{
        // Zero
        .{ .input = 0, .expected = 0 },

        // 1-8 bits (1 byte)
        .{ .input = 1, .expected = 1 },
        .{ .input = 0x7F, .expected = 1 },
        .{ .input = 0xFF, .expected = 1 },

        // 9-16 bits (2 bytes)
        .{ .input = 0x100, .expected = 2 },
        .{ .input = 0xFFFF, .expected = 2 },

        // 17-24 bits (3 bytes)
        .{ .input = 0x10000, .expected = 3 },
        .{ .input = 0xFFFFFF, .expected = 3 },

        // 25-32 bits (4 bytes)
        .{ .input = 0x1000000, .expected = 4 },
        .{ .input = 0xFFFFFFFF, .expected = 4 },

        // 33-40 bits (5 bytes)
        .{ .input = 0x100000000, .expected = 5 },
        .{ .input = 0xFFFFFFFFFF, .expected = 5 },

        // 57-64 bits (8 bytes)
        .{ .input = 0x100000000000000, .expected = 8 },
        .{ .input = 0xFFFFFFFFFFFFFFFF, .expected = 8 },
    };

    for (test_cases) |tc| {
        const val = U256.fromU64(tc.input);
        try expectEqual(tc.expected, val.byteLen());
    }

    // 192 bits = 24 bytes (high bit set in limb[2])
    const val_24 = U256{ .limbs = .{ 0, 0, 0x8000000000000000, 0 } };
    try expectEqual(24, val_24.byteLen());

    // Exactly 16 bytes (128 bits)
    const val_16 = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0, 0 } };
    try expectEqual(16, val_16.byteLen());

    // Maximum value (256 bits = 32 bytes)
    try expectEqual(32, U256.MAX.byteLen());
}

test "U256: format" {
    var buf: [100]u8 = undefined;

    // Test zero
    var fbs = std.io.fixedBufferStream(&buf);
    try U256.ZERO.format(fbs.writer());
    try expectEqualStrings("0x0", fbs.getWritten());

    // Test one
    fbs.reset();
    try U256.ONE.format(fbs.writer());
    try expectEqualStrings("0x1", fbs.getWritten());

    // Test a larger value
    fbs.reset();
    const val = U256.fromU64(0xABCDEF);
    try val.format(fbs.writer());
    try expectEqualStrings("0xabcdef", fbs.getWritten());

    // Test with multiple limbs
    fbs.reset();
    const big_val = U256{ .limbs = .{ 0x1111111111111111, 0x2222222222222222, 0, 0 } };
    try big_val.format(fbs.writer());
    try expectEqualStrings("0x22222222222222221111111111111111", fbs.getWritten());
}

test "U256: eql" {
    const a = U256.fromU64(42);
    const b = U256.fromU64(42);
    const c = U256.fromU64(43);

    try expect(a.eql(b));
    try expect(!a.eql(c));
    try expect(U256.ZERO.eql(U256.ZERO));
    try expect(!U256.ZERO.eql(U256.ONE));
}

test "U256: lt and gt" {
    const a = U256.fromU64(10);
    const b = U256.fromU64(20);

    try expect(a.lt(b));
    try expect(!b.lt(a));
    try expect(!a.lt(a));

    try expect(b.gt(a));
    try expect(!a.gt(b));
    try expect(!a.gt(a));

    // Test with multi-limb values
    const big = U256{ .limbs = .{ 0, 1, 0, 0 } }; // 2^64
    const small = U256.fromU64(0xFFFFFFFFFFFFFFFF);

    try expect(small.lt(big));
    try expect(big.gt(small));
}

test "U256: lte and gte" {
    const a = U256.fromU64(10);
    const b = U256.fromU64(20);
    const c = U256.fromU64(10);

    try expect(a.lte(b));
    try expect(a.lte(c));
    try expect(!b.lte(a));

    try expect(b.gte(a));
    try expect(a.gte(c));
    try expect(!a.gte(b));
}

test "U256: slt - signed less than" {

    // Positive numbers
    const pos1 = U256.fromU64(10);
    const pos2 = U256.fromU64(20);
    try expect(pos1.slt(pos2));
    try expect(!pos2.slt(pos1));

    // Negative number (MSB set)
    const neg1 = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } }; // -1
    const neg2 = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } }; // -2

    // -2 < -1
    try expect(neg2.slt(neg1));
    try expect(!neg1.slt(neg2));

    // Negative < Positive
    try expect(neg1.slt(pos1));
    try expect(!pos1.slt(neg1));
}

test "U256: sgt - signed greater than" {

    // Positive numbers
    const pos1 = U256.fromU64(10);
    const pos2 = U256.fromU64(20);
    try expect(pos2.sgt(pos1));
    try expect(!pos1.sgt(pos2));

    // Negative number (MSB set)
    const neg1 = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } }; // -1
    const neg2 = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } }; // -2

    // -1 > -2
    try expect(neg1.sgt(neg2));
    try expect(!neg2.sgt(neg1));

    // Positive > Negative
    try expect(pos1.sgt(neg1));
    try expect(!neg1.sgt(pos1));
}

test "U256: bitAnd" {
    const a = U256.fromU64(0b1111_0000);
    const b = U256.fromU64(0b1010_1010);
    const result = a.bitAnd(b);

    try expectEqual(0b1010_0000, result.toU64().?);

    // Test with all ones and zeros
    try expect(U256.MAX.bitAnd(U256.ZERO).eql(U256.ZERO));
    try expect(U256.MAX.bitAnd(U256.MAX).eql(U256.MAX));
}

test "U256: bitOr" {
    const a = U256.fromU64(0b1111_0000);
    const b = U256.fromU64(0b1010_1010);
    const result = a.bitOr(b);

    try expectEqual(0b1111_1010, result.toU64().?);

    // Test with all ones and zeros
    try expect(U256.ZERO.bitOr(U256.ZERO).eql(U256.ZERO));
    try expect(U256.MAX.bitOr(U256.ZERO).eql(U256.MAX));
}

test "U256: bitXor" {
    const a = U256.fromU64(0b1111_0000);
    const b = U256.fromU64(0b1010_1010);
    const result = a.bitXor(b);

    try expectEqual(0b0101_1010, result.toU64().?);

    // Test XOR properties
    const val = U256.fromU64(12345);
    try expect(val.bitXor(val).eql(U256.ZERO)); // x ^ x = 0
    try expect(val.bitXor(U256.ZERO).eql(val)); // x ^ 0 = x
}

test "U256: bitNot" {
    const zero_not = U256.ZERO.bitNot();
    try expect(zero_not.eql(U256.MAX));

    const max_not = U256.MAX.bitNot();
    try expect(max_not.eql(U256.ZERO));

    const val = U256.fromU64(0xFF);
    const not_val = val.bitNot();
    // NOT 0xFF = 0xFFFF...FF00
    try expectEqual(0xFFFFFFFFFFFFFF00, not_val.limbs[0]);
    try expectEqual(0xFFFFFFFFFFFFFFFF, not_val.limbs[1]);
}

test "U256: byte extraction" {

    // Create a value with known bytes in little-endian limbs
    const val = U256{
        .limbs = .{
            0x1F1E1D1C1B1A1918, // LSB limb: bytes 24-31 in big-endian view
            0x1716151413121110, // bytes 16-23
            0x0F0E0D0C0B0A0908, // bytes 8-15
            0x0706050403020100, // MSB limb: bytes 0-7 in big-endian view
        },
    };

    // EVM BYTE opcode: index 0 is MSB (big-endian indexing)
    try expectEqual(0x07, val.byte(0)); // Most significant byte
    try expectEqual(0x06, val.byte(1));
    try expectEqual(0x00, val.byte(7));
    try expectEqual(0x0F, val.byte(8));
    try expectEqual(0x18, val.byte(31)); // Least significant byte

    // Out of bounds
    try expectEqual(0, val.byte(32));
    try expectEqual(0, val.byte(255));
}

test "U256: shl - left shift" {

    // Shift by 0
    const val = U256.fromU64(0xFF);
    try expect(val.shl(0).eql(val));

    // Shift by small amount: 0x1 << 8 = 0x100 (256 in decimal)
    const a = U256.fromU64(1);
    const shifted = a.shl(8);
    try expectEqual(256, shifted.toU64().?);

    // Shift across limb boundary: 0x1 << 64 moves to limb[1]
    // Result: limbs = [0x0, 0x1, 0x0, 0x0] = 0x10000000000000000
    const b = U256.fromU64(1);
    const shifted_limb = b.shl(64);
    try expectEqual(0, shifted_limb.limbs[0]);
    try expectEqual(1, shifted_limb.limbs[1]);

    // Shift across limb and bit boundary within limb: 0x1 << 65 moves to limb[1] and w/i the limb
    // Result: limbs = [0x0, 0x10, 0x0, 0x0] = 0x10_0000000000000000
    const c = U256.fromU64(1);
    const shifted_limb1 = c.shl(65);
    try expectEqual(0, shifted_limb1.limbs[0]);
    try expectEqual(2, shifted_limb1.limbs[1]);

    // Shift by 256 or more = zero
    try expect(val.shl(256).eql(U256.ZERO));
    try expect(val.shl(300).eql(U256.ZERO));
}

test "U256: shr - logical right shift" {

    // Shift by 0
    const val = U256.fromU64(0xFF00);
    try expect(val.shr(0).eql(val));

    // Shift by small amount: 0xFF00 >> 8 = 0xFF
    const shifted = val.shr(8);
    try expectEqual(0xFF, shifted.toU64().?);

    // Shift across limb boundary: 0x10000000000000000 >> 64 = 0x1
    // Before: limbs = [0x0, 0x1, 0x0, 0x0], After: limbs = [0x1, 0x0, 0x0, 0x0]
    const b = U256{ .limbs = .{ 0, 1, 0, 0 } }; // 2^64
    const shifted_limb = b.shr(64);
    try expectEqual(1, shifted_limb.limbs[0]);
    try expectEqual(0, shifted_limb.limbs[1]);

    // Shift by 256 or more = zero
    try expect(val.shr(256).eql(U256.ZERO));
}

test "U256: sar - arithmetic right shift" {

    // Positive number: behaves like logical shift
    const pos = U256.fromU64(0xFF00);
    const pos_shifted = pos.sar(8);
    try expectEqual(0xFF, pos_shifted.toU64().?);

    // Negative number: fills with 1s
    // Before: limbs[3] = 0x8000000000000000 (MSB set, negative in 2's complement)
    // After SAR 8: limbs[3] = 0xFF80000000000000 (sign-extended with 0xFF)
    const neg = U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } }; // MSB set
    const neg_shifted = neg.sar(8);
    // High byte should be filled with 1s
    try expectEqual(0xFF80000000000000, neg_shifted.limbs[3]);

    // Shift negative by >= 256: returns all 1s
    const neg_all = U256.MAX;
    const shifted_max = neg_all.sar(256);
    try expect(shifted_max.eql(U256.MAX));

    // Shift positive by >= 256: returns zero
    const pos_all = U256.fromU64(123);
    const shifted_zero = pos_all.sar(300);
    try expect(shifted_zero.eql(U256.ZERO));
}

test "U256: signExtend" {

    // Extend a positive value (MSB of byte 0 is 0)
    const pos = U256.fromU64(0x7F); // 0b0111_1111
    const extended_pos = pos.signExtend(0);
    try expectEqual(0x7F, extended_pos.toU64().?);

    // Extend a negative value (MSB of byte 0 is 1)
    const neg = U256.fromU64(0xFF); // 0b1111_1111 (negative in signed byte)
    const extended_neg = neg.signExtend(0);
    // Should fill all higher bytes with 0xFF
    try expect(extended_neg.eql(U256.MAX));

    // Extend from byte 1
    const val = U256.fromU64(0x7FFF); // Positive 16-bit value
    const ext1 = val.signExtend(1);
    try expectEqual(0x7FFF, ext1.toU64().?);

    const val2 = U256.fromU64(0xFFFF); // Negative 16-bit value
    const ext2 = val2.signExtend(1);
    try expect(ext2.eql(U256.MAX));

    // Extend from byte 31: no change
    const val3 = U256.fromU64(12345);
    try expect(val3.signExtend(31).eql(val3));
}

test "U256: add - basic" {

    // Simple addition
    const a = U256.fromU64(10);
    const b = U256.fromU64(20);
    const sum = a.add(b);
    try expectEqual(30, sum.toU64().?);

    // Add zero
    const val = U256.fromU64(42);
    try expect(val.add(U256.ZERO).eql(val));
    try expect(U256.ZERO.add(val).eql(val));

    // Commutative property
    try expect(a.add(b).eql(b.add(a)));
}

test "U256: add - carry across limbs" {

    // Add 1 to max u64 in limb[0] - should carry to limb[1]
    const a = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0, 0, 0 } };
    const b = U256.fromU64(1);
    const sum = a.add(b);

    try expectEqual(0, sum.limbs[0]);
    try expectEqual(1, sum.limbs[1]);
    try expectEqual(0, sum.limbs[2]);
    try expectEqual(0, sum.limbs[3]);
}

test "U256: add - wrapping overflow" {

    // MAX + 1 = 0 (wraps around)
    const sum = U256.MAX.add(U256.ONE);
    try expect(sum.eql(U256.ZERO));

    // MAX + 2 = 1
    const sum2 = U256.MAX.add(U256.fromU64(2));
    try expect(sum2.eql(U256.ONE));

    // MAX + MAX = MAX - 1 (due to wrapping)
    const sum3 = U256.MAX.add(U256.MAX);
    const expected = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    try expect(sum3.eql(expected));
}

test "U256: sub - basic" {

    // Simple subtraction
    const a = U256.fromU64(30);
    const b = U256.fromU64(10);
    const diff = a.sub(b);
    try expectEqual(20, diff.toU64().?);

    // Subtract zero
    const val = U256.fromU64(42);
    try expect(val.sub(U256.ZERO).eql(val));

    // Subtract self = 0
    try expect(val.sub(val).eql(U256.ZERO));
}

test "U256: sub - borrow across limbs" {

    // Subtract 1 from value with limb[0] = 0 - should borrow from limb[1]
    const a = U256{ .limbs = .{ 0, 1, 0, 0 } }; // 2^64
    const b = U256.fromU64(1);
    const diff = a.sub(b);

    try expectEqual(0xFFFFFFFFFFFFFFFF, diff.limbs[0]);
    try expectEqual(0, diff.limbs[1]);
    try expectEqual(0, diff.limbs[2]);
}

test "U256: sub - wrapping underflow" {

    // 0 - 1 = MAX (wraps around)
    const diff = U256.ZERO.sub(U256.ONE);
    try expect(diff.eql(U256.MAX));

    // 1 - 2 = MAX (wraps around)
    const diff2 = U256.ONE.sub(U256.fromU64(2));
    try expect(diff2.eql(U256.MAX));

    // 10 - 20 wraps around
    const a = U256.fromU64(10);
    const b = U256.fromU64(20);
    const diff3 = a.sub(b);
    // 10 - 20 = -10 = 2^256 - 10
    const expected = U256.MAX.sub(U256.fromU64(9)); // MAX - 9 = 2^256 - 10
    try expect(diff3.eql(expected));
}

test "U256: checkedAdd - no overflow" {
    const a = U256.fromU64(10);
    const b = U256.fromU64(20);

    const sum = a.checkedAdd(b);
    try expect(sum != null);
    try expectEqual(30, sum.?.toU64().?);
}

test "U256: checkedAdd - overflow detection" {

    // MAX + 1 should overflow
    const sum1 = U256.MAX.checkedAdd(U256.ONE);
    try expect(sum1 == null);

    // MAX + MAX should overflow
    const sum2 = U256.MAX.checkedAdd(U256.MAX);
    try expect(sum2 == null);

    // Large value + 1 that doesn't overflow
    const large = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    const sum3 = large.checkedAdd(U256.ONE);
    try expect(sum3 != null);
    try expect(sum3.?.eql(U256.MAX));
}

test "U256: checkedSub - no underflow" {
    const a = U256.fromU64(30);
    const b = U256.fromU64(10);

    const diff = a.checkedSub(b);
    try expect(diff != null);
    try expectEqual(20, diff.?.toU64().?);
}

test "U256: checkedSub - underflow detection" {

    // 0 - 1 should underflow
    const diff1 = U256.ZERO.checkedSub(U256.ONE);
    try expect(diff1 == null);

    // 10 - 20 should underflow
    const a = U256.fromU64(10);
    const b = U256.fromU64(20);
    const diff2 = a.checkedSub(b);
    try expect(diff2 == null);

    // 1 - 1 = 0 (no underflow)
    const diff3 = U256.ONE.checkedSub(U256.ONE);
    try expect(diff3 != null);
    try expect(diff3.?.eql(U256.ZERO));
}

test "U256: add and sub are inverses" {
    const a = U256.fromU64(12345);
    const b = U256.fromU64(67890);

    // (a + b) - b = a
    const sum = a.add(b);
    const diff = sum.sub(b);
    try expect(diff.eql(a));

    // (a - b) + b = a (when no underflow)
    const c = U256.fromU64(100);
    const d = U256.fromU64(30);
    const diff2 = c.sub(d);
    const sum2 = diff2.add(d);
    try expect(sum2.eql(c));
}

test "U256: mul - basic" {

    // Simple multiplication
    const a = U256.fromU64(10);
    const b = U256.fromU64(20);
    const product = a.mul(b);
    try expectEqual(200, product.toU64().?);

    // Multiply by zero
    try expect(a.mul(U256.ZERO).eql(U256.ZERO));
    try expect(U256.ZERO.mul(a).eql(U256.ZERO));

    // Multiply by one
    try expect(a.mul(U256.ONE).eql(a));

    // Commutative property
    try expect(a.mul(b).eql(b.mul(a)));
}

test "U256: mul - large values" {

    // Test with larger values
    const a = U256.fromU64(0xFFFFFFFFFFFFFFFF); // max u64
    const b = U256.fromU64(2);
    const product = a.mul(b);

    // 2^64 - 1 * 2 = 2^65 - 2
    try expectEqual(0xFFFFFFFFFFFFFFFE, product.limbs[0]);
    try expectEqual(1, product.limbs[1]);
}

test "U256: mul - wrapping overflow" {

    // MAX * 2 wraps
    const product = U256.MAX.mul(U256.fromU64(2));
    const expected = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    try expect(product.eql(expected));
}

test "U256: div - basic" {

    // Simple division
    const a = U256.fromU64(100);
    const b = U256.fromU64(10);
    const quotient = a.div(b);
    try expectEqual(10, quotient.toU64().?);

    // Divide by one
    try expect(a.div(U256.ONE).eql(a));

    // Divide by self
    try expect(a.div(a).eql(U256.ONE));

    // Divide smaller by larger = 0
    try expect(b.div(a).eql(U256.ZERO));
}

test "U256: div - divide by zero" {
    const a = U256.fromU64(100);
    // EVM spec: division by zero returns zero
    try expect(a.div(U256.ZERO).eql(U256.ZERO));
}

test "U256: rem - basic" {

    // Simple modulo
    const a = U256.fromU64(100);
    const b = U256.fromU64(30);
    const remainder = a.rem(b);
    try expectEqual(10, remainder.toU64().?);

    // Modulo by larger number = self
    const c = U256.fromU64(20);
    try expect(c.rem(a).eql(c));

    // Modulo by one = 0
    try expect(a.rem(U256.ONE).eql(U256.ZERO));

    // Modulo by self = 0
    try expect(a.rem(a).eql(U256.ZERO));
}

test "U256: rem - modulo by zero" {
    const a = U256.fromU64(100);
    // EVM spec: modulo by zero returns zero
    try expect(a.rem(U256.ZERO).eql(U256.ZERO));
}

test "U256: div and rem relationship" {
    const a = U256.fromU64(12345);
    const b = U256.fromU64(678);

    // a = (a / b) * b + (a % b)
    const quotient = a.div(b);
    const remainder = a.rem(b);
    const reconstructed = quotient.mul(b).add(remainder);

    try expect(reconstructed.eql(a));
}

test "U256: sdiv - signed division" {

    // Positive / positive
    const pos1 = U256.fromU64(20);
    const pos2 = U256.fromU64(4);
    try expectEqual(5, pos1.sdiv(pos2).toU64().?);

    // Negative / positive (represented as two's complement)
    const neg = U256.MAX; // -1 in two's complement
    const pos = U256.fromU64(2);
    const result = neg.sdiv(pos);
    // -1 / 2 = 0 (truncates toward zero)
    try expect(result.eql(U256.ZERO));

    // Divide by zero
    try expect(pos1.sdiv(U256.ZERO).eql(U256.ZERO));
}

test "U256: sdiv - MIN_I256 / -1 overflow" {
    // Special case: MIN_I256 / -1 overflows in two's complement
    // MIN_I256 = 0x8000...0000 (most significant bit set)
    // -1 = 0xFFFF...FFFF (all bits set)
    // The result would be 2^255 which doesn't fit, so it wraps to MIN_I256
    const MIN_I256 = U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } };
    const neg_one = U256.MAX; // -1 in two's complement

    const result = MIN_I256.sdiv(neg_one);
    try expect(result.eql(MIN_I256));
}

test "U256: srem - signed modulo" {

    // Positive % positive
    const pos1 = U256.fromU64(22);
    const pos2 = U256.fromU64(5);
    try expectEqual(2, pos1.srem(pos2).toU64().?);

    // Modulo by zero
    try expect(pos1.srem(U256.ZERO).eql(U256.ZERO));
}

test "U256: srem - MIN_I256 % -1" {
    // Special case: MIN_I256 % -1 = 0
    // (MIN_I256 / -1 = MIN_I256 with remainder 0)
    const MIN_I256 = U256{ .limbs = .{ 0, 0, 0, 0x8000000000000000 } };
    const neg_one = U256.MAX; // -1 in two's complement

    const result = MIN_I256.srem(neg_one);
    try expect(result.eql(U256.ZERO));
}

test "U256: addmod - basic" {
    const a = U256.fromU64(10);
    const b = U256.fromU64(15);
    const m = U256.fromU64(7);

    // (10 + 15) % 7 = 25 % 7 = 4
    const result = a.addmod(b, m);
    try expectEqual(4, result.toU64().?);

    // Modulus of zero returns zero
    try expect(a.addmod(b, U256.ZERO).eql(U256.ZERO));

    // Modulus of one returns zero
    try expect(a.addmod(b, U256.ONE).eql(U256.ZERO));
}

test "U256: addmod - with overflow" {

    // Test when a + b would overflow
    const a = U256.MAX;
    const b = U256.fromU64(10);
    const m = U256.fromU64(100);

    const result = a.addmod(b, m);
    // Should handle overflow correctly
    try expect(!result.isZero());
}

test "U256: mulmod - basic" {
    const a = U256.fromU64(10);
    const b = U256.fromU64(15);
    const m = U256.fromU64(7);

    // (10 * 15) % 7 = 150 % 7 = 3
    const result = a.mulmod(b, m);
    try expectEqual(3, result.toU64().?);

    // Modulus of zero returns zero
    try expect(a.mulmod(b, U256.ZERO).eql(U256.ZERO));

    // Multiply by zero
    try expect(U256.ZERO.mulmod(b, m).eql(U256.ZERO));
}

test "U256: mulmod - large values" {

    // Test with values that would overflow in multiplication
    const a = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0, 0 } };
    const b = U256.fromU64(10);
    const m = U256.fromU64(1000);

    const result = a.mulmod(b, m);
    // Should handle overflow correctly
    try expect(!result.isZero());
}

test "U256: exp - basic" {

    // 2^8 = 256
    const base = U256.fromU64(2);
    const exponent = U256.fromU64(8);
    const result = base.exp(exponent);
    try expectEqual(256, result.toU64().?);

    // 0^n = 0 (for n > 0)
    try expect(U256.ZERO.exp(U256.fromU64(5)).eql(U256.ZERO));

    // n^0 = 1
    try expect(base.exp(U256.ZERO).eql(U256.ONE));

    // 1^n = 1
    try expect(U256.ONE.exp(exponent).eql(U256.ONE));

    // n^1 = n
    try expect(base.exp(U256.ONE).eql(base));
}

test "U256: exp - larger exponents" {

    // 3^4 = 81
    const base = U256.fromU64(3);
    const exponent = U256.fromU64(4);
    const result = base.exp(exponent);
    try expectEqual(81, result.toU64().?);

    // 10^3 = 1000
    const base2 = U256.fromU64(10);
    const exp2 = U256.fromU64(3);
    const result2 = base2.exp(exp2);
    try expectEqual(1000, result2.toU64().?);
}

test "U256: exp - wrapping overflow" {

    // Large exponentiation that wraps
    const base = U256.fromU64(2);
    const exponent = U256.fromU64(256);
    const result = base.exp(exponent);

    // 2^256 mod 2^256 = 0
    try expect(result.eql(U256.ZERO));
}
