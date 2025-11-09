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
const handlers = @import("instructions/mod.zig");

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

            .JUMP => try handlers.opJump(&self.stack),

            .JUMPI => try handlers.opJumpi(&self.stack),

            .JUMPDEST => handlers.opJumpdest(),

            .PC => try handlers.opPc(&self.stack),

            .GAS => try handlers.opGas(&self.stack),

            .RETURN => try handlers.opReturn(&self.stack),

            .REVERT => try handlers.opRevert(&self.stack),

            // ================================================================
            // Stack Operations
            // ================================================================

            .POP => {
                _ = try self.stack.pop();
            },

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

            .ADD => try handlers.opAdd(&self.stack),
            .MUL => try handlers.opMul(&self.stack),
            .SUB => try handlers.opSub(&self.stack),
            .DIV => try handlers.opDiv(&self.stack),
            .MOD => try handlers.opMod(&self.stack),
            .SDIV => try handlers.opSdiv(&self.stack),
            .SMOD => try handlers.opSmod(&self.stack),
            .ADDMOD => try handlers.opAddmod(&self.stack),
            .MULMOD => try handlers.opMulmod(&self.stack),

            .EXP => {
                // EXP has dynamic gas based on exponent byte length
                const exponent = try self.stack.peek(0);
                const exp_bytes: u8 = @intCast(exponent.byteLen());
                try self.gas.consume(cost_fns.expCost(self.spec, exp_bytes));

                try handlers.opExp(&self.stack);
            },

            .SIGNEXTEND => try handlers.opSignextend(&self.stack),

            // ================================================================
            // Comparison Operations
            // ================================================================

            .LT => try handlers.opLt(&self.stack),
            .GT => try handlers.opGt(&self.stack),
            .SLT => try handlers.opSlt(&self.stack),
            .SGT => try handlers.opSgt(&self.stack),
            .EQ => try handlers.opEq(&self.stack),
            .ISZERO => try handlers.opIszero(&self.stack),

            // ================================================================
            // Bitwise Operations
            // ================================================================

            .AND => try handlers.opAnd(&self.stack),
            .OR => try handlers.opOr(&self.stack),
            .XOR => try handlers.opXor(&self.stack),
            .NOT => try handlers.opNot(&self.stack),
            .BYTE => try handlers.opByte(&self.stack),
            .SHL => try handlers.opShl(&self.stack),
            .SHR => try handlers.opShr(&self.stack),
            .SAR => try handlers.opSar(&self.stack),

            // ================================================================
            // Cryptographic Operations
            // ================================================================

            .KECCAK256 => try handlers.opKeccak256(&self.stack, &self.memory),

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

            .SLOAD => try handlers.opSload(&self.stack),
            .SSTORE => try handlers.opSstore(&self.stack),
            .TLOAD => try handlers.opTload(&self.stack),
            .TSTORE => try handlers.opTstore(&self.stack),

            // ================================================================
            // System Operations
            // ================================================================

            .CREATE => try handlers.opCreate(&self.stack),
            .CREATE2 => try handlers.opCreate2(&self.stack),
            .CALL => try handlers.opCall(&self.stack),
            .CALLCODE => try handlers.opCallcode(&self.stack),
            .DELEGATECALL => try handlers.opDelegatecall(&self.stack),
            .STATICCALL => try handlers.opStaticcall(&self.stack),
            .SELFDESTRUCT => try handlers.opSelfdestruct(&self.stack),

            // ================================================================
            // Environmental Operations
            // ================================================================

            .ADDRESS => try handlers.opAddress(&self.stack),
            .BALANCE => try handlers.opBalance(&self.stack),
            .ORIGIN => try handlers.opOrigin(&self.stack),
            .CALLER => try handlers.opCaller(&self.stack),
            .CALLVALUE => try handlers.opCallvalue(&self.stack),
            .CALLDATALOAD => try handlers.opCalldataload(&self.stack),
            .CALLDATASIZE => try handlers.opCalldatasize(&self.stack),
            .CALLDATACOPY => try handlers.opCalldatacopy(&self.stack),
            .CODESIZE => try handlers.opCodesize(&self.stack),
            .CODECOPY => try handlers.opCodecopy(&self.stack),
            .GASPRICE => try handlers.opGasprice(&self.stack),
            .EXTCODESIZE => try handlers.opExtcodesize(&self.stack),
            .EXTCODECOPY => try handlers.opExtcodecopy(&self.stack),
            .RETURNDATASIZE => try handlers.opReturndatasize(&self.stack),
            .RETURNDATACOPY => try handlers.opReturndatacopy(&self.stack),
            .EXTCODEHASH => try handlers.opExtcodehash(&self.stack),
            .BLOCKHASH => try handlers.opBlockhash(&self.stack),
            .COINBASE => try handlers.opCoinbase(&self.stack),
            .TIMESTAMP => try handlers.opTimestamp(&self.stack),
            .NUMBER => try handlers.opNumber(&self.stack),
            .PREVRANDAO => try handlers.opPrevrandao(&self.stack),
            .GASLIMIT => try handlers.opGaslimit(&self.stack),
            .CHAINID => try handlers.opChainid(&self.stack),
            .SELFBALANCE => try handlers.opSelfbalance(&self.stack),
            .BASEFEE => try handlers.opBasefee(&self.stack),
            .BLOBHASH => try handlers.opBlobhash(&self.stack),
            .BLOBBASEFEE => try handlers.opBlobbasefee(&self.stack),

            // ================================================================
            // Logging Operations
            // ================================================================

            .LOG0 => try handlers.opLog0(&self.stack),
            .LOG1 => try handlers.opLog1(&self.stack),
            .LOG2 => try handlers.opLog2(&self.stack),
            .LOG3 => try handlers.opLog3(&self.stack),
            .LOG4 => try handlers.opLog4(&self.stack),

            // ================================================================
            // Special Operations
            // ================================================================

            .INVALID => try handlers.opInvalid(),
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
