//! This module contains operations that query execution environment information.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Address = @import("../../primitives/address.zig").Address;
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
/// Stack: [...] -> [address, ...]
pub fn opCaller(interp: *Interpreter) !void {
    const caller_u256 = U256.fromBeBytesPadded(&interp.env.tx.caller.inner.bytes);
    try interp.ctx.stack.push(caller_u256);
}

/// Get deposited value (CALLVALUE).
///
/// Stack: [...] -> [value, ...]
pub fn opCallvalue(interp: *Interpreter) !void {
    try interp.ctx.stack.push(interp.env.tx.value);
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
    const size = U256.fromU64(@intCast(interp.return_data_buffer.len));
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

    const return_data = interp.return_data_buffer;

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
