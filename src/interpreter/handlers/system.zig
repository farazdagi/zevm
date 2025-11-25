//! System operation instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Address = @import("../../primitives/address.zig").Address;
const Interpreter = @import("../interpreter.zig").Interpreter;
const CallExecutor = @import("../../CallExecutor.zig");
const CreateExecutor = @import("../../CreateExecutor.zig");
const ExecutionStatus = @import("../interpreter.zig").ExecutionStatus;

/// Create a new contract (CREATE).
///
/// Stack: [value, offset, size, ...] → [address, ...]
///
/// Performs contract creation by executing init code and deploying the resulting runtime code.
/// The new contract's address is deterministically calculated from the creator's address and nonce.
///
/// EIPs: EIP-150 (63/64 gas rule), EIP-3860 (init code size limit in Shanghai+)
pub fn opCreate(interp: *Interpreter) Interpreter.Error!void {
    return createImpl(interp, .CREATE);
}

/// Create a new contract with deterministic address (CREATE2) - EIP-1014.
///
/// Stack: [value, offset, size, salt, ...] → [address, ...]
///
/// Like CREATE, but the address is deterministically calculated from:
/// keccak256(0xff ++ sender ++ salt ++ keccak256(init_code))[12:]
///
/// This enables counterfactual instantiation and proxy patterns.
///
/// EIPs: EIP-1014 (CREATE2), EIP-150 (63/64 gas), EIP-3860 (init code size limit)
pub fn opCreate2(interp: *Interpreter) Interpreter.Error!void {
    return createImpl(interp, .CREATE2);
}

/// Variant for comptime-parameterized create implementation.
const CreateVariant = enum { CREATE, CREATE2 };

/// Shared implementation for CREATE and CREATE2 opcodes.
///
/// EIPs: EIP-150 (63/64 gas rule), EIP-1014 (CREATE2), EIP-3860 (init code size limit)
fn createImpl(interp: *Interpreter, comptime variant: CreateVariant) Interpreter.Error!void {
    // Disallow in static context.
    if (interp.is_static) return error.StateWriteInStaticCall;

    // Pop stack parameters.
    const value, const offset, const size = try interp.ctx.stack.popN(3, .{ U256, usize, usize });

    // Pop salt for CREATE2 only.
    const salt = if (variant == .CREATE2) try interp.ctx.stack.pop() else undefined;

    // Read init_code from memory.
    // Note: Dynamic gas for memory expansion already charged.
    const init_code = if (size > 0)
        try interp.ctx.memory.getSlice(offset, size)
    else
        &[_]u8{};

    // Calculate gas to send using EIP-150 63/64 rule.
    // Available gas = gas remaining after dynamic costs (including init code metering) charged.
    const gas_remaining = interp.gas.limit -| interp.gas.used;

    // Cap at 63/64 of remaining gas.
    const max_gas = gas_remaining -| (gas_remaining / 64);

    // CREATE/CREATE2 sends all available gas (no user-specified limit).
    const gas_limit = max_gas;
    if (gas_limit == 0) return error.OutOfGas;

    // Consume the gas_limit from current frame.
    // This will be refunded based on actual usage.
    try interp.gas.consume(gas_limit);

    // Build creation inputs.
    const inputs = CreateExecutor.Inputs{
        .caller = interp.ctx.contract.address,
        .kind = if (variant == .CREATE2) .{ .CREATE2 = salt } else .CREATE,
        .value = value,
        .init_code = init_code,
        .gas_limit = gas_limit,
    };

    // Execute the creation via CreateExecutor.
    const result = interp.create_executor.create(inputs) catch {
        // Handle errors from creation as failed creation.
        // All gas sent is consumed on error.
        // No return data on error.
        interp.return_data_buffer.* = &[_]u8{};
        try interp.ctx.stack.push(U256.ZERO);
        return;
    };

    // Refund unused gas.
    const gas_refund = gas_limit -| result.gas_used;
    interp.gas.used -|= gas_refund;

    // Update return data buffer.
    interp.return_data_buffer.* = result.output;

    // Push result address to stack (0x0 on failure).
    const return_address = if (result.address) |addr|
        U256.fromBeBytesPadded(&addr.inner.bytes)
    else
        U256.ZERO;

    try interp.ctx.stack.push(return_address);
}

/// Call another contract (CALL).
///
/// Stack: [gas, address, value, argsOffset, argsSize, retOffset, retSize, ...] -> [success, ...]
///
/// Performs a message call to another contract with value transfer.
/// The called contract executes with its own context (storage, address).
///
/// EIPs: EIP-150 (63/64 gas rule), EIP-2929 (cold/warm access)
pub fn opCall(interp: *Interpreter) !void {
    // Pop 7 values from stack.
    const gas_u256, const address_u256, const value_u256, const args_offset, const args_size, const ret_offset, const ret_size = try interp.ctx.stack.popN(7, .{ U256, U256, U256, usize, usize, usize, usize });

    // Convert address (last 20 bytes of U256).
    const target = Address.fromU256(address_u256);

    // Calculate gas to send using EIP-150 63/64 rule.
    // Available gas = gas remaining after dynamic costs charged.
    const gas_remaining = interp.gas.limit -| interp.gas.used;

    // Cap at 63/64 of remaining gas.
    const max_gas = gas_remaining -| (gas_remaining / 64);

    // User-specified gas, capped at max.
    const requested_gas = gas_u256.toU64() orelse max_gas;
    var gas_to_send = @min(requested_gas, max_gas);

    // Add gas stipend if transferring value (EIP-150).
    const has_value = !value_u256.isZero();
    if (has_value) {
        gas_to_send +|= interp.spec.call_stipend;
    }

    // Consume the gas we're sending (will be refunded if call succeeds with gas left).
    try interp.gas.consume(gas_to_send -| (if (has_value) interp.spec.call_stipend else 0));

    // Copy input data from memory.
    const input_data = if (args_size > 0)
        try interp.ctx.memory.getSlice(args_offset, args_size)
    else
        &[_]u8{};

    // Build call inputs.
    const inputs = CallExecutor.Inputs{
        .kind = .CALL,
        .target = target,
        .caller = interp.ctx.contract.address,
        .value = value_u256,
        .input = input_data,
        .gas_limit = gas_to_send,
        .transfer_value = true,
    };

    // Execute the call.
    const result = interp.call_executor.call(inputs) catch {
        // Handle errors from call as failed calls.
        // These errors (InsufficientBalance, InvalidLength, etc.) should not propagate
        // but instead result in a failed call (push 0 to stack).
        // All gas sent is consumed on error.
        // No return data on error.
        interp.return_data_buffer.* = &[_]u8{};
        try interp.ctx.stack.push(U256.ZERO);
        return;
    };

    // Copy return data to memory (truncated to ret_length).
    if (ret_size > 0) {
        const copy_len = @min(ret_size, result.output.len);
        if (copy_len > 0) {
            // Ensure memory is expanded (gas already charged by dynamic gas function).
            try interp.ctx.memory.ensureCapacity(ret_offset, ret_size);
            const dest = try interp.ctx.memory.getSliceMut(ret_offset, copy_len);
            @memcpy(dest, result.output[0..copy_len]);
        }
        // Zero-fill any remaining space if return data is shorter than ret_length.
        if (copy_len < ret_size) {
            const remaining = try interp.ctx.memory.getSliceMut(ret_offset + copy_len, ret_size - copy_len);
            @memset(remaining, 0);
        }
    }

    // Refund unused gas.
    const gas_refund = gas_to_send -| result.gas_used;
    interp.gas.used -|= gas_refund;

    // Add sub-call refunds to our refund counter.
    interp.gas.adjustRefund(result.gas_refund);

    // Push success (1) or failure (0) to stack.
    const success: u64 = if (result.status == .SUCCESS) 1 else 0;
    try interp.ctx.stack.push(U256.fromU64(success));
}

/// Call another contract's code in current context (CALLCODE).
///
/// Stack: [gas, address, value, argsOffset, argsSize, retOffset, retSize, ...] -> [success, ...]
///
/// Executes target's code in the current contract's context (storage, address).
/// Unlike DELEGATECALL, msg.sender is the current contract (not preserved from parent).
/// Unlike CALL, no actual value transfer occurs (but gas stipend still applies if value > 0).
///
/// Note: Deprecated in favor of DELEGATECALL. Required for backwards compatibility.
/// EIPs: EIP-150 (63/64 gas rule), EIP-2929 (cold/warm access)
pub fn opCallcode(interp: *Interpreter) !void {
    // Pop 7 values from stack (same as CALL).
    const gas_u256, const address_u256, const value_u256, const args_offset, const args_size, const ret_offset, const ret_size = try interp.ctx.stack.popN(7, .{ U256, U256, U256, usize, usize, usize, usize });

    // Convert address (last 20 bytes of U256).
    const target = Address.fromU256(address_u256);

    // Calculate gas to send using EIP-150 63/64 rule.
    const gas_remaining = interp.gas.limit -| interp.gas.used;
    const max_gas = gas_remaining -| (gas_remaining / 64);
    const requested_gas = gas_u256.toU64() orelse max_gas;
    var gas_to_send = @min(requested_gas, max_gas);

    // Add gas stipend if value > 0 (same as CALL, even though no transfer occurs).
    const has_value = !value_u256.isZero();
    if (has_value) {
        gas_to_send +|= interp.spec.call_stipend;
    }

    // Consume the gas we're sending.
    try interp.gas.consume(gas_to_send -| (if (has_value) interp.spec.call_stipend else 0));

    // Copy input data from memory.
    const input_data = if (args_size > 0)
        try interp.ctx.memory.getSlice(args_offset, args_size)
    else
        &[_]u8{};

    // Build call inputs.
    // Key differences from CALL:
    // kind = .CALLCODE (executes in caller's context)
    // transfer_value = false (no actual ETH transfer)
    const inputs = CallExecutor.Inputs{
        .kind = .CALLCODE,
        .target = target,
        .caller = interp.ctx.contract.address,
        .value = value_u256,
        .input = input_data,
        .gas_limit = gas_to_send,
        .transfer_value = false,
    };

    // Execute the call.
    const result = interp.call_executor.call(inputs) catch {
        // Handle errors as failed calls (push 0 to stack).
        interp.return_data_buffer.* = &[_]u8{};
        try interp.ctx.stack.push(U256.ZERO);
        return;
    };

    // Copy return data to memory.
    if (ret_size > 0) {
        const copy_len = @min(ret_size, result.output.len);
        if (copy_len > 0) {
            try interp.ctx.memory.ensureCapacity(ret_offset, ret_size);
            const dest = try interp.ctx.memory.getSliceMut(ret_offset, copy_len);
            @memcpy(dest, result.output[0..copy_len]);
        }
        if (copy_len < ret_size) {
            const remaining = try interp.ctx.memory.getSliceMut(ret_offset + copy_len, ret_size - copy_len);
            @memset(remaining, 0);
        }
    }

    // Refund unused gas.
    const gas_refund = gas_to_send -| result.gas_used;
    interp.gas.used -|= gas_refund;

    // Add sub-call refunds.
    interp.gas.adjustRefund(result.gas_refund);

    // Push success (1) or failure (0).
    const success: u64 = if (result.status == .SUCCESS) 1 else 0;
    try interp.ctx.stack.push(U256.fromU64(success));
}

/// Call another contract's code in current context (DELEGATECALL) - EIP-7.
///
/// Stack: [gas, address, argsOffset, argsSize, retOffset, retSize, ...] -> [success, ...]
///
/// Executes target's code in the current contract's context.
/// msg.sender and msg.value are preserved from the current frame.
/// Storage operations apply to the current contract.
///
/// EIPs: EIP-7 (Homestead), EIP-150 (63/64 gas rule)
pub fn opDelegatecall(interp: *Interpreter) !void {
    // Pop 6 values from stack (no value parameter).
    const gas_u256, const address_u256, const args_offset, const args_size, const ret_offset, const ret_size = try interp.ctx.stack.popN(6, .{ U256, U256, usize, usize, usize, usize });

    // Convert address (last 20 bytes of U256).
    const target = Address.fromU256(address_u256);

    // Calculate gas to send using EIP-150 63/64 rule.
    const gas_remaining = interp.gas.limit -| interp.gas.used;
    const max_gas = gas_remaining -| (gas_remaining / 64);
    const requested_gas = gas_u256.toU64() orelse max_gas;
    const gas_to_send = @min(requested_gas, max_gas);

    // Consume the gas we're sending.
    try interp.gas.consume(gas_to_send);

    // Copy input data from memory.
    const input_data = if (args_size > 0)
        try interp.ctx.memory.getSlice(args_offset, args_size)
    else
        &[_]u8{};

    // Build call inputs.
    // DELEGATECALL preserves caller and value from the current frame.
    // The context address (for storage) is set to caller by Evm.call().
    const inputs = CallExecutor.Inputs{
        .kind = .DELEGATECALL,
        .target = target,
        .caller = interp.ctx.contract.caller, // Preserved from parent
        .value = interp.ctx.contract.value, // Preserved from parent
        .input = input_data,
        .gas_limit = gas_to_send,
        .transfer_value = false, // DELEGATECALL never transfers value
    };

    // Execute the call.
    const result = interp.call_executor.call(inputs) catch {
        interp.return_data_buffer.* = &[_]u8{};
        try interp.ctx.stack.push(U256.ZERO);
        return;
    };

    // Copy return data to memory.
    if (ret_size > 0) {
        const copy_len = @min(ret_size, result.output.len);
        if (copy_len > 0) {
            try interp.ctx.memory.ensureCapacity(ret_offset, ret_size);
            const dest = try interp.ctx.memory.getSliceMut(ret_offset, copy_len);
            @memcpy(dest, result.output[0..copy_len]);
        }
        if (copy_len < ret_size) {
            const remaining = try interp.ctx.memory.getSliceMut(ret_offset + copy_len, ret_size - copy_len);
            @memset(remaining, 0);
        }
    }

    // Refund unused gas.
    const gas_refund = gas_to_send -| result.gas_used;
    interp.gas.used -|= gas_refund;

    // Add sub-call refunds.
    interp.gas.adjustRefund(result.gas_refund);

    // Push success (1) or failure (0) to stack.
    const success: u64 = if (result.status == .SUCCESS) 1 else 0;
    try interp.ctx.stack.push(U256.fromU64(success));
}

/// Static call to another contract (STATICCALL) - EIP-214.
///
/// Stack: [gas, address, argsOffset, argsSize, retOffset, retSize, ...] -> [success, ...]
///
/// Performs a read-only call to another contract.
/// Any state modifications in the called code will revert.
///
/// EIPs: EIP-214 (Byzantium), EIP-150 (63/64 gas rule)
pub fn opStaticcall(interp: *Interpreter) !void {
    // Pop 6 values from stack (no value parameter).
    const gas_u256, const address_u256, const args_offset, const args_size, const ret_offset, const ret_size = try interp.ctx.stack.popN(6, .{ U256, U256, usize, usize, usize, usize });

    // Convert address (last 20 bytes of U256).
    const target = Address.fromU256(address_u256);

    // Calculate gas to send using EIP-150 63/64 rule.
    const gas_remaining = interp.gas.limit -| interp.gas.used;
    const max_gas = gas_remaining -| (gas_remaining / 64);
    const requested_gas = gas_u256.toU64() orelse max_gas;
    const gas_to_send = @min(requested_gas, max_gas);

    // Consume the gas we're sending.
    try interp.gas.consume(gas_to_send);

    // Copy input data from memory.
    const input_data = if (args_size > 0)
        try interp.ctx.memory.getSlice(args_offset, args_size)
    else
        &[_]u8{};

    // Build call inputs.
    // STATICCALL: caller is current contract, value is always zero.
    const inputs = CallExecutor.Inputs{
        .kind = .STATICCALL,
        .target = target,
        .caller = interp.ctx.contract.address, // Current contract
        .value = U256.ZERO, // Always zero for STATICCALL
        .input = input_data,
        .gas_limit = gas_to_send,
        .transfer_value = false, // STATICCALL never transfers value
    };

    // Execute the call.
    const result = interp.call_executor.call(inputs) catch {
        interp.return_data_buffer.* = &[_]u8{};
        try interp.ctx.stack.push(U256.ZERO);
        return;
    };

    // Copy return data to memory.
    if (ret_size > 0) {
        const copy_len = @min(ret_size, result.output.len);
        if (copy_len > 0) {
            try interp.ctx.memory.ensureCapacity(ret_offset, ret_size);
            const dest = try interp.ctx.memory.getSliceMut(ret_offset, copy_len);
            @memcpy(dest, result.output[0..copy_len]);
        }
        if (copy_len < ret_size) {
            const remaining = try interp.ctx.memory.getSliceMut(ret_offset + copy_len, ret_size - copy_len);
            @memset(remaining, 0);
        }
    }

    // Refund unused gas.
    const gas_refund = gas_to_send -| result.gas_used;
    interp.gas.used -|= gas_refund;

    // Add sub-call refunds.
    interp.gas.adjustRefund(result.gas_refund);

    // Push success (1) or failure (0) to stack.
    const success: u64 = if (result.status == .SUCCESS) 1 else 0;
    try interp.ctx.stack.push(U256.fromU64(success));
}

/// Destroy contract and send funds (SELFDESTRUCT).
///
/// Stack: [..., address] -> []
/// Note: This operation requires state modifications and special handling.
/// It will be handled specially in the interpreter's execute() function.
pub fn opSelfdestruct(interp: *Interpreter) !void {
    // SELFDESTRUCT is not allowed in static call context (STATICCALL).
    if (interp.is_static) {
        return error.StateWriteInStaticCall;
    }
    return error.UnimplementedOpcode;
}

// ============================================================================
// Tests
// ============================================================================
