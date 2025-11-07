//! Bytecode Interpreter
//!
//! Executes EVM bytecode using a fetch-decode-execute loop.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Stack = @import("stack.zig").Stack;
const Memory = @import("memory.zig").Memory;
const Gas = @import("gas/accounting.zig").Gas;
const Spec = @import("../hardfork/spec.zig").Spec;
const Opcode = @import("opcode.zig").Opcode;
const U256 = @import("../primitives/big.zig").U256;
const cost_fns = @import("gas/cost_fns.zig");

// Instruction handlers
const arithmetic = @import("instructions/arithmetic.zig");
const comparison = @import("instructions/comparison.zig");
const bitwise = @import("instructions/bitwise.zig");
const crypto = @import("instructions/crypto.zig");
const memory_ops = @import("instructions/memory_ops.zig");
const control = @import("instructions/control.zig");
const storage = @import("instructions/storage.zig");
const system = @import("instructions/system.zig");
const environmental = @import("instructions/environmental.zig");
const logging = @import("instructions/logging.zig");

/// Execution status after interpreter completes.
pub const ExecutionStatus = enum {
    /// Execution completed successfully
    SUCCESS,

    /// Execution reverted (REVERT opcode)
    REVERT,

    /// Ran out of gas
    OUT_OF_GAS,

    /// Stack overflow (> 1024 items)
    STACK_OVERFLOW,

    /// Stack underflow (not enough items for operation)
    STACK_UNDERFLOW,

    /// Invalid opcode or unimplemented opcode
    INVALID_OPCODE,

    /// Invalid jump destination
    INVALID_JUMP,

    /// Invalid program counter (beyond bytecode)
    INVALID_PC,
};

/// Result of interpreter execution.
pub const InterpreterResult = struct {
    /// Execution status
    status: ExecutionStatus,

    /// Total gas used
    gas_used: u64,

    /// Gas refunded (capped per EIP-3529)
    gas_refund: u64,

    /// Return data (from RETURN or REVERT)
    return_data: ?[]const u8,
};

/// EVM bytecode interpreter.
///
/// Executes bytecode using a fetch-decode-execute loop with centralized
/// program counter management. Instruction handlers are pure functions
/// that operate on the interpreter's components (stack, memory, gas).
pub const Interpreter = struct {
    /// All errors that can occur during interpreter execution.
    pub const Error = Stack.Error || Memory.Error || Gas.Error || error{
        InvalidOpcode,
        UnimplementedOpcode,
        InvalidJump,
        InvalidProgramCounter,
    };

    /// Bytecode to execute
    bytecode: []const u8,

    /// Program counter (index into bytecode)
    pc: usize,

    /// Stack
    stack: Stack,

    /// Gas accounting
    gas: Gas,

    /// Memory
    memory: Memory,

    /// Spec (fork-specific rules and costs)
    spec: Spec,

    /// Allocator for dynamic memory
    allocator: Allocator,

    /// Return data (set by RETURN or REVERT)
    return_data: ?[]const u8,

    /// Whether execution has halted
    is_halted: bool,

    /// Initialize interpreter with bytecode and gas limit.
    pub fn init(allocator: Allocator, bytecode: []const u8, spec: Spec, gas_limit: u64) !Interpreter {
        return Interpreter{
            .allocator = allocator,
            .bytecode = bytecode,
            .pc = 0,
            .stack = try Stack.init(allocator),
            .memory = try Memory.init(allocator),
            .gas = Gas.init(gas_limit, spec),
            .spec = spec,
            .is_halted = false,
            .return_data = null,
        };
    }

    /// Clean up allocated resources.
    pub fn deinit(self: *Interpreter) void {
        self.stack.deinit();
        self.memory.deinit();
        // return_data is owned by the caller after extracting from result
    }

    /// Execute bytecode until halted or error.
    ///
    /// Returns the execution result including status, gas used, and return data.
    pub fn run(self: *Interpreter) !InterpreterResult {
        while (!self.is_halted) {
            self.step() catch |err| {
                return self.handleError(err);
            };
        }

        return self.buildResult();
    }

    /// Execute one instruction (fetch-decode-execute).
    pub fn step(self: *Interpreter) !void {
        // Verify we're not going beyond bytecode bounds.
        if (self.pc >= self.bytecode.len) {
            return error.InvalidProgramCounter;
        }

        // Fetch and decode opcode byte
        const opcode_byte = self.bytecode[self.pc];
        const opcode = try Opcode.fromByte(opcode_byte);

        // Ensure there are enough bytes for this opcode's immediates.
        const required_bytes = 1 + opcode.immediateBytes();
        if (self.pc + required_bytes > self.bytecode.len) {
            return error.InvalidProgramCounter;
        }

        // Charge *base* gas, some instructions may require additional dynamically calculated gas.
        // CRITICAL: Gas MUST be charged before execution to prevent side effects (on out of gas).
        try self.gas.consume(opcode.baseCost(self.spec));

        // Execute instruction
        try self.execute(opcode);

        // Control flow opcodes (JUMP, RETURN, STOP, etc.) set is_halted or modify PC themselves.
        // All other opcodes advance by 1 + immediate_bytes.
        if (!self.is_halted and !opcode.isControlFlow()) {
            self.pc += 1 + opcode.immediateBytes();
        }
    }

    /// Execute the given opcode.
    ///
    /// This is the main dispatch table.
    /// Special cases that need direct interpreter state access (e.g. PUSH) are handled inline.
    fn execute(self: *Interpreter, opcode: Opcode) !void {
        switch (opcode) {
            // ================================================================
            // Control Flow
            // ================================================================

            .STOP => {
                self.is_halted = true;
            },

            // ================================================================
            // Stack Operations
            // ================================================================

            .POP => try control.pop(&self.stack),

            .PUSH0 => {
                // EIP-3855: PUSH0 pushes 0 without reading immediates
                if (!self.spec.has_push0) return error.InvalidOpcode;
                try self.stack.push(U256.ZERO);
            },

            // PUSH1-PUSH32: Push 1-32 bytes onto stack
            // With centralized PC management, we just read immediates and push
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8, .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16, .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24, .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => {
                // Read immediate bytes (bounds are already checked in step())
                const num_bytes = opcode.immediateBytes();
                const bytes = self.bytecode[self.pc + 1 ..][0..num_bytes];

                const value = U256.fromBeBytesPadded(bytes);
                try self.stack.push(value);
            },

            // DUP1-DUP16: Duplicate Nth stack item (N=1 is top)
            // Opcode values are sequential: 0x80-0x8F
            .DUP1, .DUP2, .DUP3, .DUP4, .DUP5, .DUP6, .DUP7, .DUP8, .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16 => {
                const index = @intFromEnum(opcode) - @intFromEnum(Opcode.DUP1) + 1;
                try self.stack.dup(index);
            },

            // SWAP1-SWAP16: Swap top with Nth item (N=1 is second item)
            // Opcode values are sequential: 0x90-0x9F
            .SWAP1, .SWAP2, .SWAP3, .SWAP4, .SWAP5, .SWAP6, .SWAP7, .SWAP8, .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16 => {
                const index = @intFromEnum(opcode) - @intFromEnum(Opcode.SWAP1) + 1;
                try self.stack.swap(index);
            },

            // ================================================================
            // Arithmetic Operations
            // ================================================================

            .ADD => try arithmetic.add(&self.stack),
            .MUL => try arithmetic.mul(&self.stack),
            .SUB => try arithmetic.sub(&self.stack),
            .DIV => try arithmetic.div(&self.stack),
            .MOD => try arithmetic.mod(&self.stack),

            .SDIV => try arithmetic.sdiv(&self.stack),
            .SMOD => try arithmetic.smod(&self.stack),
            .ADDMOD => try arithmetic.addmod(&self.stack),
            .MULMOD => try arithmetic.mulmod(&self.stack),

            .EXP => {
                // EXP has dynamic gas based on exponent byte length
                const exponent = try self.stack.peek(0);
                const exp_bytes: u8 = @intCast(exponent.byteLen());
                try self.gas.consume(cost_fns.expCost(self.spec, exp_bytes));

                try arithmetic.exp(&self.stack);
            },

            .SIGNEXTEND => try arithmetic.signextend(&self.stack),

            // ================================================================
            // Comparison Operations
            // ================================================================

            .LT => try comparison.lt(&self.stack),
            .GT => try comparison.gt(&self.stack),
            .SLT => try comparison.slt(&self.stack),
            .SGT => try comparison.sgt(&self.stack),
            .EQ => try comparison.eq(&self.stack),
            .ISZERO => try comparison.iszero(&self.stack),

            // ================================================================
            // Bitwise Operations
            // ================================================================

            .AND => try bitwise.and_op(&self.stack),
            .OR => try bitwise.or_op(&self.stack),
            .XOR => try bitwise.xor_op(&self.stack),
            .NOT => try bitwise.not_op(&self.stack),
            .BYTE => try bitwise.byte_op(&self.stack),
            .SHL => try bitwise.shl(&self.stack),
            .SHR => try bitwise.shr(&self.stack),
            .SAR => try bitwise.sar(&self.stack),

            // ================================================================
            // Cryptographic Operations
            // ================================================================

            .KECCAK256 => try crypto.keccak256(&self.stack, &self.memory),

            // ================================================================
            // Memory Operations
            // ================================================================

            .MLOAD => try memory_ops.mload(&self.stack, &self.memory),
            .MSTORE => try memory_ops.mstore(&self.stack, &self.memory),
            .MSTORE8 => try memory_ops.mstore8(&self.stack, &self.memory),
            .MSIZE => try memory_ops.msize(&self.stack, &self.memory),
            .MCOPY => try memory_ops.mcopy(&self.stack, &self.memory),

            // ================================================================
            // Storage Operations
            // ================================================================

            .SLOAD => try storage.sload(&self.stack),
            .SSTORE => try storage.sstore(&self.stack),
            .TLOAD => try storage.tload(&self.stack),
            .TSTORE => try storage.tstore(&self.stack),

            // ================================================================
            // Control Flow (Complex)
            // ================================================================

            .JUMP => try control.jump(&self.stack),
            .JUMPI => try control.jumpi(&self.stack),
            .JUMPDEST => control.jumpdest(),
            .PC => try control.pc(&self.stack),
            .GAS => try control.gas(&self.stack),
            .RETURN => try control.return_op(&self.stack),
            .REVERT => try control.revert(&self.stack),

            // ================================================================
            // System Operations
            // ================================================================

            .CREATE => try system.create(&self.stack),
            .CREATE2 => try system.create2(&self.stack),
            .CALL => try system.call(&self.stack),
            .CALLCODE => try system.callcode(&self.stack),
            .DELEGATECALL => try system.delegatecall(&self.stack),
            .STATICCALL => try system.staticcall(&self.stack),
            .SELFDESTRUCT => try system.selfdestruct(&self.stack),

            // ================================================================
            // Environmental Operations
            // ================================================================

            .ADDRESS => try environmental.address(&self.stack),
            .BALANCE => try environmental.balance(&self.stack),
            .ORIGIN => try environmental.origin(&self.stack),
            .CALLER => try environmental.caller(&self.stack),
            .CALLVALUE => try environmental.callvalue(&self.stack),
            .CALLDATALOAD => try environmental.calldataload(&self.stack),
            .CALLDATASIZE => try environmental.calldatasize(&self.stack),
            .CALLDATACOPY => try environmental.calldatacopy(&self.stack),
            .CODESIZE => try environmental.codesize(&self.stack),
            .CODECOPY => try environmental.codecopy(&self.stack),
            .GASPRICE => try environmental.gasprice(&self.stack),
            .EXTCODESIZE => try environmental.extcodesize(&self.stack),
            .EXTCODECOPY => try environmental.extcodecopy(&self.stack),
            .RETURNDATASIZE => try environmental.returndatasize(&self.stack),
            .RETURNDATACOPY => try environmental.returndatacopy(&self.stack),
            .EXTCODEHASH => try environmental.extcodehash(&self.stack),
            .BLOCKHASH => try environmental.blockhash(&self.stack),
            .COINBASE => try environmental.coinbase(&self.stack),
            .TIMESTAMP => try environmental.timestamp(&self.stack),
            .NUMBER => try environmental.number(&self.stack),
            .PREVRANDAO => try environmental.prevrandao(&self.stack),
            .GASLIMIT => try environmental.gaslimit(&self.stack),
            .CHAINID => try environmental.chainid(&self.stack),
            .SELFBALANCE => try environmental.selfbalance(&self.stack),
            .BASEFEE => try environmental.basefee(&self.stack),
            .BLOBHASH => try environmental.blobhash(&self.stack),
            .BLOBBASEFEE => try environmental.blobbasefee(&self.stack),

            // ================================================================
            // Logging Operations
            // ================================================================

            .LOG0 => try logging.log0(&self.stack),
            .LOG1 => try logging.log1(&self.stack),
            .LOG2 => try logging.log2(&self.stack),
            .LOG3 => try logging.log3(&self.stack),
            .LOG4 => try logging.log4(&self.stack),

            // ================================================================
            // Special Operations
            // ================================================================

            .INVALID => try control.invalid(),
        }
    }

    /// Convert a Zig error to an ExecutionStatus.
    fn handleError(self: *Interpreter, err: Error) InterpreterResult {
        const status: ExecutionStatus = switch (err) {
            error.StackOverflow => .STACK_OVERFLOW,
            error.StackUnderflow => .STACK_UNDERFLOW,
            error.OutOfGas => .OUT_OF_GAS,
            error.OutOfMemory => .OUT_OF_GAS,
            error.InvalidOffset, error.IntegerOverflow => .INVALID_OPCODE,
            error.InvalidOpcode, error.UnimplementedOpcode, error.InvalidProgramCounter => .INVALID_OPCODE,
            error.InvalidJump => .INVALID_JUMP,
        };

        return InterpreterResult{
            .status = status,
            .gas_used = self.gas.used,
            .gas_refund = self.gas.finalRefund(),
            .return_data = null,
        };
    }

    /// Build the successful execution result.
    fn buildResult(self: *Interpreter) InterpreterResult {
        return InterpreterResult{
            .status = .SUCCESS,
            .gas_used = self.gas.used,
            .gas_refund = self.gas.finalRefund(),
            .return_data = self.return_data,
        };
    }
};
