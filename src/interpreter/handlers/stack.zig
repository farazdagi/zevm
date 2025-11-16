//! Stack manipulation instruction handlers.

const std = @import("std");
const Interpreter = @import("../interpreter.zig").Interpreter;
const U256 = @import("../../primitives/big.zig").U256;
const Opcode = @import("../opcode.zig").Opcode;

/// Generic handler for PUSH1-PUSH32.
///
/// Reads 1-32 immediate bytes following the opcode and pushes the value onto the stack.
/// The number of bytes is determined from the opcode value (0x60=PUSH1, 0x7F=PUSH32).
pub fn opPushN(interp: *Interpreter) !void {
    // Get the current opcode to determine how many bytes to push
    const opcode = Opcode.fromByte(interp.ctx.contract.bytecode.raw[interp.pc]);

    // Read immediate bytes (bounds already checked in step())
    const bytes = interp.ctx.contract.bytecode.raw[interp.pc + 1 ..][0..opcode.immediateBytes()];

    const value = U256.fromBeBytesPadded(bytes);
    try interp.ctx.stack.push(value);
}

/// Generic handler for DUP1-DUP16.
///
/// Duplicates the Nth stack item (N=1 is top) and pushes it.
/// The index is calculated from the opcode value (0x80=DUP1, 0x8F=DUP16).
pub fn opDupN(interp: *Interpreter) !void {
    const opcode_byte = interp.ctx.contract.bytecode.raw[interp.pc];
    const index = opcode_byte - 0x7F; // DUP1=0x80, so 0x80-0x7F=1
    try interp.ctx.stack.dup(index);
}

/// Generic handler for SWAP1-SWAP16.
///
/// Swaps the top stack item with the Nth item (N=1 is second item).
/// The index is calculated from the opcode value (0x90=SWAP1, 0x9F=SWAP16).
pub fn opSwapN(interp: *Interpreter) !void {
    const opcode_byte = interp.ctx.contract.bytecode.raw[interp.pc];
    const index = opcode_byte - 0x8F; // SWAP1=0x90, so 0x90-0x8F=1
    try interp.ctx.stack.swap(index);
}

/// Handler for POP.
///
/// Removes the top stack item.
pub fn opPop(interp: *Interpreter) !void {
    _ = try interp.ctx.stack.pop();
}

/// Handler for PUSH0 (EIP-3855).
///
/// Pushes zero onto the stack without reading immediates.
pub fn opPush0(interp: *Interpreter) !void {
    if (!interp.spec.has_push0) return error.InvalidOpcode;
    try interp.ctx.stack.push(U256.ZERO);
}
