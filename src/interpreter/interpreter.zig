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

    const Self = @This();

    /// Initialize interpreter with bytecode and gas limit.
    pub fn init(allocator: Allocator, bytecode: []const u8, spec: Spec, gas_limit: u64) !Self {
        return Self{
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
    pub fn deinit(self: *Self) void {
        self.stack.deinit();
        self.memory.deinit();
        // return_data is owned by the caller after extracting from result
    }

    /// Execute bytecode until halted or error.
    ///
    /// Returns the execution result including status, gas used, and return data.
    pub fn run(self: *Self) !InterpreterResult {
        while (!self.is_halted) {
            self.step() catch |err| {
                return self.handleError(err);
            };
        }

        return self.buildResult();
    }

    /// Execute one instruction (fetch-decode-execute).
    pub fn step(self: *Self) !void {
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
    fn execute(self: *Self, opcode: Opcode) !void {
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

            .POP => try control.opPop(&self.stack),

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

            .ADD => try arithmetic.opAdd(&self.stack),
            .MUL => try arithmetic.opMul(&self.stack),
            .SUB => try arithmetic.opSub(&self.stack),
            .DIV => try arithmetic.opDiv(&self.stack),
            .MOD => try arithmetic.opMod(&self.stack),

            .SDIV => try arithmetic.opSdiv(&self.stack),
            .SMOD => try arithmetic.opSmod(&self.stack),
            .ADDMOD => try arithmetic.opAddmod(&self.stack),
            .MULMOD => try arithmetic.opMulmod(&self.stack),

            .EXP => {
                // EXP has dynamic gas based on exponent byte length
                const exponent = try self.stack.peek(0);
                const exp_bytes: u8 = @intCast(exponent.byteLen());
                try self.gas.consume(cost_fns.expCost(self.spec, exp_bytes));

                try arithmetic.opExp(&self.stack);
            },

            .SIGNEXTEND => try arithmetic.opSignextend(&self.stack),

            // ================================================================
            // Comparison Operations
            // ================================================================

            .LT => try comparison.opLt(&self.stack),
            .GT => try comparison.opGt(&self.stack),
            .SLT => try comparison.opSlt(&self.stack),
            .SGT => try comparison.opSgt(&self.stack),
            .EQ => try comparison.opEq(&self.stack),
            .ISZERO => try comparison.opIszero(&self.stack),

            // ================================================================
            // Bitwise Operations
            // ================================================================

            .AND => try bitwise.opAnd(&self.stack),
            .OR => try bitwise.opOr(&self.stack),
            .XOR => try bitwise.opXor(&self.stack),
            .NOT => try bitwise.opNot(&self.stack),
            .BYTE => try bitwise.opByte(&self.stack),
            .SHL => try bitwise.opShl(&self.stack),
            .SHR => try bitwise.opShr(&self.stack),
            .SAR => try bitwise.opSar(&self.stack),

            // ================================================================
            // Cryptographic Operations
            // ================================================================

            .KECCAK256 => try crypto.opKeccak256(&self.stack, &self.memory),

            // ================================================================
            // Memory Operations
            // ================================================================

            .MLOAD => try memory_ops.opMload(&self.stack, &self.memory),
            .MSTORE => try memory_ops.opMstore(&self.stack, &self.memory),
            .MSTORE8 => try memory_ops.opMstore8(&self.stack, &self.memory),
            .MSIZE => try memory_ops.opMsize(&self.stack, &self.memory),
            .MCOPY => try memory_ops.opMcopy(&self.stack, &self.memory),

            // ================================================================
            // Storage Operations
            // ================================================================

            .SLOAD => try storage.opSload(&self.stack),
            .SSTORE => try storage.opSstore(&self.stack),
            .TLOAD => try storage.opTload(&self.stack),
            .TSTORE => try storage.opTstore(&self.stack),

            // ================================================================
            // Control Flow (Complex)
            // ================================================================

            .JUMP => try control.opJump(&self.stack),
            .JUMPI => try control.opJumpi(&self.stack),
            .JUMPDEST => control.opJumpdest(),
            .PC => try control.opPc(&self.stack),
            .GAS => try control.opGas(&self.stack),
            .RETURN => try control.opReturn(&self.stack),
            .REVERT => try control.opRevert(&self.stack),

            // ================================================================
            // System Operations
            // ================================================================

            .CREATE => try system.opCreate(&self.stack),
            .CREATE2 => try system.opCreate2(&self.stack),
            .CALL => try system.opCall(&self.stack),
            .CALLCODE => try system.opCallcode(&self.stack),
            .DELEGATECALL => try system.opDelegatecall(&self.stack),
            .STATICCALL => try system.opStaticcall(&self.stack),
            .SELFDESTRUCT => try system.opSelfdestruct(&self.stack),

            // ================================================================
            // Environmental Operations
            // ================================================================

            .ADDRESS => try environmental.opAddress(&self.stack),
            .BALANCE => try environmental.opBalance(&self.stack),
            .ORIGIN => try environmental.opOrigin(&self.stack),
            .CALLER => try environmental.opCaller(&self.stack),
            .CALLVALUE => try environmental.opCallvalue(&self.stack),
            .CALLDATALOAD => try environmental.opCalldataload(&self.stack),
            .CALLDATASIZE => try environmental.opCalldatasize(&self.stack),
            .CALLDATACOPY => try environmental.opCalldatacopy(&self.stack),
            .CODESIZE => try environmental.opCodesize(&self.stack),
            .CODECOPY => try environmental.opCodecopy(&self.stack),
            .GASPRICE => try environmental.opGasprice(&self.stack),
            .EXTCODESIZE => try environmental.opExtcodesize(&self.stack),
            .EXTCODECOPY => try environmental.opExtcodecopy(&self.stack),
            .RETURNDATASIZE => try environmental.opReturndatasize(&self.stack),
            .RETURNDATACOPY => try environmental.opReturndatacopy(&self.stack),
            .EXTCODEHASH => try environmental.opExtcodehash(&self.stack),
            .BLOCKHASH => try environmental.opBlockhash(&self.stack),
            .COINBASE => try environmental.opCoinbase(&self.stack),
            .TIMESTAMP => try environmental.opTimestamp(&self.stack),
            .NUMBER => try environmental.opNumber(&self.stack),
            .PREVRANDAO => try environmental.opPrevrandao(&self.stack),
            .GASLIMIT => try environmental.opGaslimit(&self.stack),
            .CHAINID => try environmental.opChainid(&self.stack),
            .SELFBALANCE => try environmental.opSelfbalance(&self.stack),
            .BASEFEE => try environmental.opBasefee(&self.stack),
            .BLOBHASH => try environmental.opBlobhash(&self.stack),
            .BLOBBASEFEE => try environmental.opBlobbasefee(&self.stack),

            // ================================================================
            // Logging Operations
            // ================================================================

            .LOG0 => try logging.opLog0(&self.stack),
            .LOG1 => try logging.opLog1(&self.stack),
            .LOG2 => try logging.opLog2(&self.stack),
            .LOG3 => try logging.opLog3(&self.stack),
            .LOG4 => try logging.opLog4(&self.stack),

            // ================================================================
            // Special Operations
            // ================================================================

            .INVALID => try control.opInvalid(),
        }
    }

    /// Convert a Zig error to an ExecutionStatus.
    fn handleError(self: *Self, err: Error) InterpreterResult {
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
    fn buildResult(self: *Self) InterpreterResult {
        return InterpreterResult{
            .status = .SUCCESS,
            .gas_used = self.gas.used,
            .gas_refund = self.gas.finalRefund(),
            .return_data = self.return_data,
        };
    }
};
