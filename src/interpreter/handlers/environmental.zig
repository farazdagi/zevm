//! This module contains operations that query execution environment information.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Address = @import("../../primitives/address.zig").Address;
const B256 = @import("../../primitives/bytes.zig").B256;
const Interpreter = @import("../interpreter.zig").Interpreter;

/// Get address of currently executing account (ADDRESS).
///
/// Stack: [...] -> [address, ...]
pub fn opAddress(interp: *Interpreter) !void {
    const address_u256 = U256.fromBeBytesPadded(&interp.ctx.contract.address.inner.bytes);
    try interp.ctx.stack.push(address_u256);
}

/// Get balance of an address (BALANCE).
///
/// Stack: [address, ...] -> [balance, ...]
pub fn opBalance(interp: *Interpreter) !void {
    const address_ptr = try interp.ctx.stack.peekMut(0);

    // Convert U256 to Address (take last 20 bytes)
    const address_bytes = address_ptr.toBeBytes();
    const address = Address.init(address_bytes[12..32].*);

    // Query balance from host and write directly to stack
    address_ptr.* = interp.host.balance(address);
}

/// Get execution origination address (ORIGIN).
///
/// Stack: [...] -> [address, ...]
pub fn opOrigin(interp: *Interpreter) !void {
    const origin_u256 = U256.fromBeBytesPadded(&interp.env.tx.origin.inner.bytes);
    try interp.ctx.stack.push(origin_u256);
}

/// Get caller address (CALLER).
///
/// Returns the address of the account that initiated this call frame (msg.sender).
/// For CALL/CALLCODE/STATICCALL: the immediate caller.
/// For DELEGATECALL: propagated from parent frame.
///
/// Stack: [...] -> [address, ...]
pub fn opCaller(interp: *Interpreter) !void {
    const caller_u256 = U256.fromBeBytesPadded(&interp.ctx.contract.caller.inner.bytes);
    try interp.ctx.stack.push(caller_u256);
}

/// Get deposited value (CALLVALUE).
///
/// Returns the value sent with this call frame (msg.value).
/// For CALL/CALLCODE: the value transferred.
/// For DELEGATECALL: propagated from parent frame (no actual transfer).
/// For STATICCALL: always zero.
///
/// Stack: [...] -> [value, ...]
pub fn opCallvalue(interp: *Interpreter) !void {
    try interp.ctx.stack.push(interp.ctx.contract.value);
}

/// Get gas price (GASPRICE).
///
/// Stack: [...] -> [price, ...]
pub fn opGasprice(interp: *Interpreter) !void {
    try interp.ctx.stack.push(interp.env.tx.gas_price);
}

/// Get balance of currently executing account (SELFBALANCE) - EIP-1884.
///
/// Stack: [...] -> [balance, ...]
pub fn opSelfbalance(interp: *Interpreter) !void {
    // Query balance of current contract
    const balance = interp.host.balance(interp.ctx.contract.address);
    try interp.ctx.stack.push(balance);
}

/// Load word from input data (CALLDATALOAD).
///
/// Stack: [offset, ...] -> [data, ...]
pub fn opCalldataload(interp: *Interpreter) !void {
    const offset_ptr = try interp.ctx.stack.peekMut(0);
    const offset = offset_ptr.toUsize() orelse {
        // Offset too large - return zero
        offset_ptr.* = U256.ZERO;
        return;
    };

    const calldata = interp.env.tx.data;

    // Read 32 bytes from calldata, padding with zeros if needed
    var word: [32]u8 = [_]u8{0} ** 32;

    if (offset < calldata.len) {
        const available = @min(32, calldata.len - offset);
        @memcpy(word[0..available], calldata[offset..][0..available]);
    }
    // If offset >= calldata.len, word is already all zeros

    offset_ptr.* = U256.fromBeBytes(&word);
}

/// Get size of input data (CALLDATASIZE).
///
/// Stack: [...] -> [size, ...]
pub fn opCalldatasize(interp: *Interpreter) !void {
    const size = U256.fromU64(@intCast(interp.env.tx.data.len));
    try interp.ctx.stack.push(size);
}

/// Copy input data to memory (CALLDATACOPY).
///
/// Stack: [destOffset, offset, length, ...] -> [...]
/// Dynamic gas cost for memory expansion is charged by the interpreter.
pub fn opCalldatacopy(interp: *Interpreter) !void {
    const dest_offset_u256 = try interp.ctx.stack.pop();
    const offset_u256 = try interp.ctx.stack.pop();
    const length_u256 = try interp.ctx.stack.pop();

    const dest_offset = dest_offset_u256.toUsize() orelse return error.InvalidOffset;
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const length = length_u256.toUsize() orelse return error.InvalidOffset;

    if (length == 0) return; // No-op for zero length

    // Ensure memory is large enough (gas already charged by dynamic gas function)
    try interp.ctx.memory.ensureCapacity(dest_offset, length);

    const calldata = interp.env.tx.data;
    const dest_slice = try interp.ctx.memory.getSliceMut(dest_offset, length);

    // Copy available data from calldata, padding with zeros if needed
    if (offset < calldata.len) {
        const available = @min(length, calldata.len - offset);
        @memcpy(dest_slice[0..available], calldata[offset..][0..available]);

        // Zero-pad remaining bytes if we read beyond calldata
        if (available < length) {
            @memset(dest_slice[available..], 0);
        }
    } else {
        // Offset is beyond calldata - fill with zeros
        @memset(dest_slice, 0);
    }
}

/// Get size of code (CODESIZE).
///
/// Stack: [...] -> [size, ...]
pub fn opCodesize(interp: *Interpreter) !void {
    const size = U256.fromU64(@intCast(interp.ctx.contract.bytecode.raw.len));
    try interp.ctx.stack.push(size);
}

/// Copy code to memory (CODECOPY).
///
/// Stack: [destOffset, offset, length, ...] -> [...]
/// Dynamic gas cost for memory expansion is charged by the interpreter.
pub fn opCodecopy(interp: *Interpreter) !void {
    const dest_offset_u256 = try interp.ctx.stack.pop();
    const offset_u256 = try interp.ctx.stack.pop();
    const length_u256 = try interp.ctx.stack.pop();

    const dest_offset = dest_offset_u256.toUsize() orelse return error.InvalidOffset;
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const length = length_u256.toUsize() orelse return error.InvalidOffset;

    if (length == 0) return; // No-op for zero length

    // Ensure memory is large enough (gas already charged by dynamic gas function)
    try interp.ctx.memory.ensureCapacity(dest_offset, length);

    const code = interp.ctx.contract.bytecode.raw;
    const dest_slice = try interp.ctx.memory.getSliceMut(dest_offset, length);

    // Copy available data from code, padding with zeros if needed
    if (offset < code.len) {
        const available = @min(length, code.len - offset);
        @memcpy(dest_slice[0..available], code[offset..][0..available]);

        // Zero-pad remaining bytes if we read beyond code
        if (available < length) {
            @memset(dest_slice[available..], 0);
        }
    } else {
        // Offset is beyond code - fill with zeros
        @memset(dest_slice, 0);
    }
}

/// Get size of external code (EXTCODESIZE).
///
/// Stack: [address, ...] -> [size, ...]
pub fn opExtcodesize(interp: *Interpreter) !void {
    const address_ptr = try interp.ctx.stack.peekMut(0);

    // Convert U256 to Address (take last 20 bytes)
    const address_bytes = address_ptr.toBeBytes();
    const address = Address.init(address_bytes[12..32].*);

    // Query code size from host and write directly to stack
    const size = interp.host.codeSize(address);
    address_ptr.* = U256.fromU64(@intCast(size));
}

/// Copy external code to memory (EXTCODECOPY).
///
/// Stack: [address, destOffset, offset, length, ...] -> [...]
/// Dynamic gas cost for memory expansion is charged by the interpreter.
pub fn opExtcodecopy(interp: *Interpreter) !void {
    const address_u256 = try interp.ctx.stack.pop();
    const dest_offset_u256 = try interp.ctx.stack.pop();
    const offset_u256 = try interp.ctx.stack.pop();
    const length_u256 = try interp.ctx.stack.pop();

    const dest_offset = dest_offset_u256.toUsize() orelse return error.InvalidOffset;
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const length = length_u256.toUsize() orelse return error.InvalidOffset;

    if (length == 0) return; // No-op for zero length

    // Convert U256 to Address (take last 20 bytes)
    const address_bytes = address_u256.toBeBytes();
    const address = Address.init(address_bytes[12..32].*);

    // Ensure memory is large enough (gas already charged by dynamic gas function)
    try interp.ctx.memory.ensureCapacity(dest_offset, length);

    // Get code from host (we own this slice and must free it)
    const code = try interp.host.code(address);
    defer interp.allocator.free(code);

    const dest_slice = try interp.ctx.memory.getSliceMut(dest_offset, length);

    // Copy available data from code, padding with zeros if needed
    if (offset < code.len) {
        const available = @min(length, code.len - offset);
        @memcpy(dest_slice[0..available], code[offset..][0..available]);

        // Zero-pad remaining bytes if we read beyond code
        if (available < length) {
            @memset(dest_slice[available..], 0);
        }
    } else {
        // Offset is beyond code - fill with zeros
        @memset(dest_slice, 0);
    }
}

/// Get hash of external code (EXTCODEHASH) - EIP-1052.
///
/// Stack: [address, ...] -> [hash, ...]
pub fn opExtcodehash(interp: *Interpreter) !void {
    const address_ptr = try interp.ctx.stack.peekMut(0);

    // Convert U256 to Address (take last 20 bytes)
    const address_bytes = address_ptr.toBeBytes();
    const address = Address.init(address_bytes[12..32].*);

    // Query code hash from host and write directly to stack
    const code_hash = interp.host.codeHash(address);
    address_ptr.* = U256.fromBeBytes(&code_hash.bytes);
}

/// Get size of return data (RETURNDATASIZE) - EIP-211.
///
/// Stack: [...] -> [size, ...]
pub fn opReturndatasize(interp: *Interpreter) !void {
    // Return data buffer lives at Evm executor level (EIP-211).
    const return_data = interp.return_data_buffer.*;
    const size = U256.fromU64(@intCast(return_data.len));
    try interp.ctx.stack.push(size);
}

/// Copy return data to memory (RETURNDATACOPY) - EIP-211.
///
/// Stack: [destOffset, offset, length, ...] -> [...]
/// Note: Reverts if offset + length > return_data_buffer.len (no zero-padding)
pub fn opReturndatacopy(interp: *Interpreter) !void {
    const dest_offset_u256 = try interp.ctx.stack.pop();
    const offset_u256 = try interp.ctx.stack.pop();
    const length_u256 = try interp.ctx.stack.pop();

    const dest_offset = dest_offset_u256.toUsize() orelse return error.InvalidOffset;
    const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
    const length = length_u256.toUsize() orelse return error.InvalidOffset;

    if (length == 0) return; // No-op for zero length

    // Return data buffer lives at Evm executor level (EIP-211).
    const return_data = interp.return_data_buffer.*;

    // Check bounds - revert if reading beyond return data (EIP-211 requirement)
    const end_offset = offset +| length; // Saturating add
    if (end_offset > return_data.len or end_offset < offset) {
        return error.InvalidOffset;
    }

    // Ensure memory is large enough (gas already charged by dynamic gas function)
    try interp.ctx.memory.ensureCapacity(dest_offset, length);

    const dest_slice = try interp.ctx.memory.getSliceMut(dest_offset, length);

    // Copy data from return_data_buffer (no zero-padding, bounds already checked)
    @memcpy(dest_slice, return_data[offset..][0..length]);
}

/// Get hash of recent complete block (BLOCKHASH).
///
/// Stack: [blockNumber, ...] -> [hash, ...]
pub fn opBlockhash(interp: *Interpreter) !void {
    const block_number_ptr = try interp.ctx.stack.peekMut(0);
    const block_number = block_number_ptr.toU64() orelse {
        // Block number too large, return zero
        block_number_ptr.* = U256.ZERO;
        return;
    };

    // Query block hash from host and write directly to stack
    const block_hash = interp.host.blockHash(block_number);
    block_number_ptr.* = U256.fromBeBytes(&block_hash.bytes);
}

/// Get block's beneficiary address (COINBASE).
///
/// Stack: [...] -> [address, ...]
pub fn opCoinbase(interp: *Interpreter) !void {
    const coinbase_u256 = U256.fromBeBytesPadded(&interp.env.block.coinbase.inner.bytes);
    try interp.ctx.stack.push(coinbase_u256);
}

/// Get block's timestamp (TIMESTAMP).
///
/// Stack: [...] -> [timestamp, ...]
pub fn opTimestamp(interp: *Interpreter) !void {
    const timestamp = U256.fromU64(interp.env.block.timestamp);
    try interp.ctx.stack.push(timestamp);
}

/// Get block's number (NUMBER).
///
/// Stack: [...] -> [number, ...]
pub fn opNumber(interp: *Interpreter) !void {
    const number = U256.fromU64(interp.env.block.number);
    try interp.ctx.stack.push(number);
}

/// Get block's difficulty / PREVRANDAO (DIFFICULTY/PREVRANDAO).
///
/// Stack: [...] -> [difficulty, ...]
/// Note: Post-merge this returns PREVRANDAO (EIP-4399)
pub fn opPrevrandao(interp: *Interpreter) !void {
    const prevrandao = U256.fromBeBytes(&interp.env.block.prevrandao.bytes);
    try interp.ctx.stack.push(prevrandao);
}

/// Get block's gas limit (GASLIMIT).
///
/// Stack: [...] -> [limit, ...]
pub fn opGaslimit(interp: *Interpreter) !void {
    const gas_limit = U256.fromU64(interp.env.block.gas_limit);
    try interp.ctx.stack.push(gas_limit);
}

/// Get chain ID (CHAINID) - EIP-1344.
///
/// Stack: [...] -> [chainId, ...]
pub fn opChainid(interp: *Interpreter) !void {
    const chain_id = U256.fromU64(interp.spec.chain_id);
    try interp.ctx.stack.push(chain_id);
}

/// Get base fee (BASEFEE) - EIP-3198.
///
/// Stack: [...] -> [baseFee, ...]
pub fn opBasefee(interp: *Interpreter) !void {
    try interp.ctx.stack.push(interp.env.block.basefee);
}

/// Get versioned hash of blob at index (BLOBHASH) - EIP-4844.
///
/// Stack: [index, ...] -> [versionedHash, ...]
pub fn opBlobhash(interp: *Interpreter) !void {
    const index_ptr = try interp.ctx.stack.peekMut(0);
    const index = index_ptr.toUsize() orelse {
        // Index too large, return zero
        index_ptr.* = U256.ZERO;
        return;
    };

    const blob_hashes = interp.env.tx.blob_hashes;

    // Return hash if index is valid, otherwise return zero
    if (index < blob_hashes.len) {
        index_ptr.* = U256.fromBeBytes(&blob_hashes[index].bytes);
    } else {
        index_ptr.* = U256.ZERO;
    }
}

/// Get blob base fee (BLOBBASEFEE) - EIP-7516.
///
/// Stack: [...] -> [blobBaseFee, ...]
pub fn opBlobbasefee(interp: *Interpreter) !void {
    try interp.ctx.stack.push(interp.env.block.blob_basefee);
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const test_helpers = @import("test_helpers.zig");
const TestContext = test_helpers.TestContext;

test "ADDRESS returns contract address" {
    const addr = try Address.fromHex("0x1234567890123456789012345678901234567890");
    var ctx = try TestContext.createWithBytecode(
        std.testing.allocator,
        &[_]u8{0x00}, // STOP
        addr,
    );
    defer ctx.destroy();

    try opAddress(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    const expected = U256.fromBeBytesPadded(&addr.inner.bytes);
    try expectEqual(expected, result);
}

test "ORIGIN returns transaction origin" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const origin_addr = try Address.fromHex("0x1111111111111111111111111111111111111111");
    ctx.env.tx.origin = origin_addr;

    try opOrigin(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    const expected = U256.fromBeBytesPadded(&origin_addr.inner.bytes);
    try expectEqual(expected, result);
}

test "CALLER returns contract caller (msg.sender)" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const caller_addr = try Address.fromHex("0x2222222222222222222222222222222222222222");
    ctx.interp.ctx.contract.caller = caller_addr;

    try opCaller(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    const expected = U256.fromBeBytesPadded(&caller_addr.inner.bytes);
    try expectEqual(expected, result);
}

test "CALLVALUE returns contract value (msg.value)" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    ctx.interp.ctx.contract.value = U256.fromU64(1000);

    try opCallvalue(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(1000), result);
}

test "GASPRICE returns gas price" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    ctx.env.tx.gas_price = U256.fromU64(50);

    try opGasprice(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(50), result);
}

test "CALLDATASIZE returns calldata length" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const calldata = [_]u8{ 0x11, 0x22, 0x33, 0x44 };
    ctx.env.tx.data = &calldata;

    try opCalldatasize(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(4), result);
}

test "CALLDATASIZE returns zero for empty calldata" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    ctx.env.tx.data = &[_]u8{};

    try opCalldatasize(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.ZERO, result);
}

test "CODESIZE returns bytecode length" {
    const bytecode = [_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }; // PUSH1 1, PUSH1 2, ADD
    var ctx = try TestContext.createWithBytecode(
        std.testing.allocator,
        &bytecode,
        Address.zero(),
    );
    defer ctx.destroy();

    try opCodesize(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(5), result);
}

test "RETURNDATASIZE returns return data buffer length" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const return_data = [_]u8{ 0xAA, 0xBB, 0xCC };
    ctx.evm.return_data_buffer = &return_data;

    try opReturndatasize(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(3), result);

    // Reset to empty so deinit doesn't try to free stack memory.
    ctx.evm.return_data_buffer = &[_]u8{};
}

test "RETURNDATASIZE returns zero for empty return data" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // EVM starts with empty return_data_buffer by default.
    try opReturndatasize(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.ZERO, result);
}

test "COINBASE returns block coinbase address" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const coinbase_addr = try Address.fromHex("0x3333333333333333333333333333333333333333");
    ctx.env.block.coinbase = coinbase_addr;

    try opCoinbase(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    const expected = U256.fromBeBytesPadded(&coinbase_addr.inner.bytes);
    try expectEqual(expected, result);
}

test "TIMESTAMP returns block timestamp" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    ctx.env.block.timestamp = 1234567890;

    try opTimestamp(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(1234567890), result);
}

test "NUMBER returns block number" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    ctx.env.block.number = 9876543;

    try opNumber(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(9876543), result);
}

test "PREVRANDAO returns prevrandao value" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const prevrandao_bytes = [_]u8{0xFF} ** 32;
    ctx.env.block.prevrandao = B256{ .bytes = prevrandao_bytes };

    try opPrevrandao(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    const expected = U256.fromBeBytes(&prevrandao_bytes);
    try expectEqual(expected, result);
}

test "GASLIMIT returns block gas limit" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    ctx.env.block.gas_limit = 30_000_000;

    try opGaslimit(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(30_000_000), result);
}

test "CHAINID returns chain ID from spec" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // Default spec in TestContext is Cancun with chain_id = 1 (mainnet)
    try opChainid(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(1), result);
}

test "BASEFEE returns block base fee" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    ctx.env.block.basefee = U256.fromU64(15);

    try opBasefee(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(15), result);
}

test "BLOBBASEFEE returns blob base fee" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    ctx.env.block.blob_basefee = U256.fromU64(25);

    try opBlobbasefee(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(25), result);
}

test "CALLDATALOAD - normal 32-byte read" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // 32 bytes of calldata
    const calldata = [_]u8{
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
    };
    ctx.env.tx.data = &calldata;

    // Load from offset 0
    try ctx.interp.ctx.stack.push(U256.ZERO);
    try opCalldataload(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    const expected = U256.fromBeBytes(&calldata);
    try expectEqual(expected, result);
}

test "CALLDATALOAD - partial read with zero padding" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const calldata = [_]u8{ 0x11, 0x22, 0x33, 0x44 }; // Only 4 bytes
    ctx.env.tx.data = &calldata;

    // Load from offset 0 (should read 4 bytes + 28 zero bytes)
    try ctx.interp.ctx.stack.push(U256.ZERO);
    try opCalldataload(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    var expected_bytes = [_]u8{0} ** 32;
    expected_bytes[0..4].* = calldata;
    const expected = U256.fromBeBytes(&expected_bytes);
    try expectEqual(expected, result);
}

test "CALLDATALOAD - offset beyond calldata returns zeros" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const calldata = [_]u8{ 0x11, 0x22 };
    ctx.env.tx.data = &calldata;

    // Load from offset 100 (beyond calldata)
    try ctx.interp.ctx.stack.push(U256.fromU64(100));
    try opCalldataload(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.ZERO, result);
}

test "CALLDATALOAD - offset overflow returns zeros" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const calldata = [_]u8{ 0x11, 0x22 };
    ctx.env.tx.data = &calldata;

    // Offset too large to fit in usize
    try ctx.interp.ctx.stack.push(U256.MAX);
    try opCalldataload(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.ZERO, result);
}

test "BALANCE - existing account" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const addr = try Address.fromHex("0x4444444444444444444444444444444444444444");
    try ctx.mock.setBalance(addr, U256.fromU64(1000));

    // Push address to stack
    const addr_u256 = U256.fromBeBytesPadded(&addr.inner.bytes);
    try ctx.interp.ctx.stack.push(addr_u256);

    try opBalance(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(1000), result);
}

test "BALANCE - non-existent account returns zero" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const addr = try Address.fromHex("0x5555555555555555555555555555555555555555");
    // Don't set balance - account doesn't exist

    const addr_u256 = U256.fromBeBytesPadded(&addr.inner.bytes);
    try ctx.interp.ctx.stack.push(addr_u256);

    try opBalance(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.ZERO, result);
}

test "SELFBALANCE returns contract's own balance" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // Contract address is from TestContext (Address.zero())
    const contract_addr = Address.zero();
    try ctx.mock.setBalance(contract_addr, U256.fromU64(500));

    try opSelfbalance(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(500), result);
}

test "EXTCODESIZE - existing account" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const addr = try Address.fromHex("0x6666666666666666666666666666666666666666");
    const code = [_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }; // 5 bytes
    try ctx.mock.setCode(addr, &code);

    const addr_u256 = U256.fromBeBytesPadded(&addr.inner.bytes);
    try ctx.interp.ctx.stack.push(addr_u256);

    try opExtcodesize(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.fromU64(5), result);
}

test "EXTCODESIZE - non-existent account returns zero" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const addr = try Address.fromHex("0x7777777777777777777777777777777777777777");
    // Don't set code

    const addr_u256 = U256.fromBeBytesPadded(&addr.inner.bytes);
    try ctx.interp.ctx.stack.push(addr_u256);

    try opExtcodesize(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.ZERO, result);
}

test "EXTCODEHASH - existing account with code" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const addr = try Address.fromHex("0x8888888888888888888888888888888888888888");
    const code = [_]u8{ 0x60, 0x01 };
    try ctx.mock.setCode(addr, &code);

    const addr_u256 = U256.fromBeBytesPadded(&addr.inner.bytes);
    try ctx.interp.ctx.stack.push(addr_u256);

    try opExtcodehash(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    // Result should be keccak256 hash of code (non-zero)
    try expect(!result.isZero());
}

test "EXTCODEHASH - non-existent account returns zero" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const addr = try Address.fromHex("0x9999999999999999999999999999999999999999");
    // Don't set code - account doesn't exist

    const addr_u256 = U256.fromBeBytesPadded(&addr.inner.bytes);
    try ctx.interp.ctx.stack.push(addr_u256);

    try opExtcodehash(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.ZERO, result);
}

test "BLOCKHASH returns hash for block number" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    // MockHost currently returns zero for all block hashes
    try ctx.interp.ctx.stack.push(U256.fromU64(100));
    try opBlockhash(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    // Just verify operation completed (MockHost returns zero)
    _ = result;
}

test "BLOBHASH - valid index returns hash" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const hash1 = B256{ .bytes = [_]u8{0x11} ** 32 };
    const hash2 = B256{ .bytes = [_]u8{0x22} ** 32 };
    const blob_hashes = [_]B256{ hash1, hash2 };
    ctx.env.tx.blob_hashes = &blob_hashes;

    // Get hash at index 0
    try ctx.interp.ctx.stack.push(U256.ZERO);
    try opBlobhash(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    const expected = U256.fromBeBytes(&hash1.bytes);
    try expectEqual(expected, result);
}

test "BLOBHASH - index out of bounds returns zero" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const hash1 = B256{ .bytes = [_]u8{0x11} ** 32 };
    const blob_hashes = [_]B256{hash1};
    ctx.env.tx.blob_hashes = &blob_hashes;

    // Get hash at index 5 (out of bounds)
    try ctx.interp.ctx.stack.push(U256.fromU64(5));
    try opBlobhash(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.ZERO, result);
}

test "BLOBHASH - index overflow returns zero" {
    var ctx = try TestContext.create(std.testing.allocator);
    defer ctx.destroy();

    const hash1 = B256{ .bytes = [_]u8{0x11} ** 32 };
    const blob_hashes = [_]B256{hash1};
    ctx.env.tx.blob_hashes = &blob_hashes;

    // Index too large to fit in usize
    try ctx.interp.ctx.stack.push(U256.MAX);
    try opBlobhash(&ctx.interp);

    const result = try ctx.interp.ctx.stack.pop();
    try expectEqual(U256.ZERO, result);
}
