//! System operation instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const Address = @import("../../primitives/address.zig").Address;
const Interpreter = @import("../interpreter.zig").Interpreter;
const CallInputs = @import("../../call_types.zig").CallInputs;
const ExecutionStatus = @import("../interpreter.zig").ExecutionStatus;

/// Create a new contract (CREATE).
///
/// Stack: [value, offset, length, ...] -> [address, ...]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub fn opCreate(interp: *Interpreter) !void {
    // CREATE is not allowed in static call context (STATICCALL).
    if (interp.is_static) {
        return error.StateWriteInStaticCall;
    }
    return error.UnimplementedOpcode;
}

/// Create a new contract with deterministic address (CREATE2) - EIP-1014.
///
/// Stack: [value, offset, length, salt, ...] -> [address, ...]
/// Note: This operation requires complex state management and sub-context execution.
/// It will be handled specially in the interpreter's execute() function.
pub fn opCreate2(interp: *Interpreter) !void {
    // CREATE2 is not allowed in static call context (STATICCALL).
    if (interp.is_static) {
        return error.StateWriteInStaticCall;
    }
    return error.UnimplementedOpcode;
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
    const gas_u256 = try interp.ctx.stack.pop();
    const address_u256 = try interp.ctx.stack.pop();
    const value_u256 = try interp.ctx.stack.pop();
    const args_offset_u256 = try interp.ctx.stack.pop();
    const args_size_u256 = try interp.ctx.stack.pop();
    const ret_offset_u256 = try interp.ctx.stack.pop();
    const ret_size_u256 = try interp.ctx.stack.pop();

    // Convert address (last 20 bytes of U256).
    const target = Address.fromU256(address_u256);

    // Convert offsets and lengths to usize.
    const args_offset = args_offset_u256.toUsize() orelse return error.InvalidOffset;
    const args_size = args_size_u256.toUsize() orelse return error.InvalidOffset;
    const ret_offset = ret_offset_u256.toUsize() orelse return error.InvalidOffset;
    const ret_size = ret_size_u256.toUsize() orelse return error.InvalidOffset;

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
    const inputs = CallInputs{
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
    interp.gas.refund(result.gas_refund);

    // Push success (1) or failure (0) to stack.
    const success: u64 = if (result.status == .SUCCESS) 1 else 0;
    try interp.ctx.stack.push(U256.fromU64(success));
}

/// Call another contract's code in current context (CALLCODE).
///
/// Stack: [gas, address, value, argsOffset, argsLength, retOffset, retLength, ...] -> [success, ...]
/// Note: Deprecated in favor of DELEGATECALL.
pub fn opCallcode(interp: *Interpreter) !void {
    _ = interp;
    return error.UnimplementedOpcode;
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
    const gas_u256 = try interp.ctx.stack.pop();
    const address_u256 = try interp.ctx.stack.pop();
    const args_offset_u256 = try interp.ctx.stack.pop();
    const args_size_u256 = try interp.ctx.stack.pop();
    const ret_offset_u256 = try interp.ctx.stack.pop();
    const ret_size_u256 = try interp.ctx.stack.pop();

    // Convert address (last 20 bytes of U256).
    const target = Address.fromU256(address_u256);

    // Convert offsets and lengths to usize.
    const args_offset = args_offset_u256.toUsize() orelse return error.InvalidOffset;
    const args_size = args_size_u256.toUsize() orelse return error.InvalidOffset;
    const ret_offset = ret_offset_u256.toUsize() orelse return error.InvalidOffset;
    const ret_size = ret_size_u256.toUsize() orelse return error.InvalidOffset;

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
    const inputs = CallInputs{
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
    interp.gas.refund(result.gas_refund);

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
    const gas_u256 = try interp.ctx.stack.pop();
    const address_u256 = try interp.ctx.stack.pop();
    const args_offset_u256 = try interp.ctx.stack.pop();
    const args_size_u256 = try interp.ctx.stack.pop();
    const ret_offset_u256 = try interp.ctx.stack.pop();
    const ret_size_u256 = try interp.ctx.stack.pop();

    // Convert address (last 20 bytes of U256).
    const target = Address.fromU256(address_u256);

    // Convert offsets and lengths to usize.
    const args_offset = args_offset_u256.toUsize() orelse return error.InvalidOffset;
    const args_size = args_size_u256.toUsize() orelse return error.InvalidOffset;
    const ret_offset = ret_offset_u256.toUsize() orelse return error.InvalidOffset;
    const ret_size = ret_size_u256.toUsize() orelse return error.InvalidOffset;

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
    const inputs = CallInputs{
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
    interp.gas.refund(result.gas_refund);

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
