//! Contract represents the bytecode being executed and its call frame parameters.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Address = @import("primitives/address.zig").Address;
const U256 = @import("primitives/big.zig").U256;
const AnalyzedBytecode = @import("interpreter/bytecode.zig").AnalyzedBytecode;

const Contract = @This();

/// The bytecode being executed (with JUMPDEST analysis).
bytecode: AnalyzedBytecode,

/// The address of this contract (context address).
///
/// This is the address where the code resides and where storage operations apply.
/// For CALL/CALLCODE/STATICCALL: the callee's address.
/// For DELEGATECALL: the caller's address (code borrowed from callee).
address: Address,

/// The caller of this execution frame (msg.sender).
///
/// For CALL/CALLCODE/STATICCALL: the immediate caller.
/// For DELEGATECALL: propagated from parent frame.
caller: Address,

/// The value sent with this call (msg.value).
///
/// For CALL/CALLCODE: the value transferred.
/// For DELEGATECALL: propagated from parent frame (no actual transfer).
/// For STATICCALL: always zero.
value: U256,

/// Allocator for cleanup.
allocator: Allocator,

/// Clean up allocated resources.
pub fn deinit(self: *Contract) void {
    self.bytecode.deinit();
}
