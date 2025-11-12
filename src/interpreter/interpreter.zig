//! Bytecode Interpreter
//!
//! Executes EVM bytecode using a fetch-decode-execute loop.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Stack = @import("stack.zig").Stack;
const Memory = @import("memory.zig").Memory;
const Gas = @import("gas/accounting.zig").Gas;
const Spec = @import("../hardfork.zig").Spec;
const Opcode = @import("opcode.zig").Opcode;
const U256 = @import("../primitives/big.zig").U256;
const cost_fns = @import("gas/cost_fns.zig");
const Bytecode = @import("bytecode.zig").Bytecode;
const AnalyzedBytecode = @import("bytecode.zig").AnalyzedBytecode;

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

/// Call-scoped execution context.
///
/// Contains the state that is local to a single execution context (call frame).
/// This includes the bytecode being executed, the operand stack, and memory.
/// When implementing CALL/DELEGATECALL/STATICCALL operations, each nested call
/// will have its own context.
pub const CallContext = struct {
    /// Analyzed bytecode (guaranteed to be executable, not EIP-7702 delegation)
    bytecode: AnalyzedBytecode,

    /// Operand stack
    stack: Stack,

    /// Call memory
    memory: Memory,

    /// Initialize a new interpreter context.
    pub fn init(allocator: Allocator, bytecode: AnalyzedBytecode) !CallContext {
        var stack = try Stack.init(allocator);
        errdefer stack.deinit();

        var memory = try Memory.init(allocator);
        errdefer memory.deinit();

        return CallContext{
            .bytecode = bytecode,
            .stack = stack,
            .memory = memory,
        };
    }

    /// Clean up allocated resources.
    pub fn deinit(self: *CallContext) void {
        self.stack.deinit();
        self.memory.deinit();
        self.bytecode.deinit();
    }
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
        InvalidOffset,
        InvalidBytecode,
        Revert,
    };

    /// Call-scoped execution context (stack, memory, bytecode)
    ctx: CallContext,

    /// Program counter (index into bytecode)
    pc: usize,

    /// Gas accounting
    gas: Gas,

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
    pub fn init(allocator: Allocator, raw_bytecode: []const u8, spec: Spec, gas_limit: u64) !Self {
        // Analyze bytecode (detects format automatically)
        var bytecode = try Bytecode.analyze(allocator, raw_bytecode);
        errdefer bytecode.deinit(allocator);

        // EIP-7702 delegation bytecode must be resolved at the Host/State layer.
        // The interpreter can only execute regular analyzed bytecode.
        const analyzed = switch (bytecode) {
            .analyzed => |b| b,
            .eip7702 => return error.InvalidBytecode,
        };

        // Create execution context with analyzed bytecode
        var ctx = try CallContext.init(allocator, analyzed);
        errdefer ctx.deinit();

        return Self{
            .allocator = allocator,
            .ctx = ctx,
            .pc = 0,
            .gas = Gas.init(gas_limit, spec),
            .spec = spec,
            .is_halted = false,
            .return_data = null,
        };
    }

    /// Clean up allocated resources.
    pub fn deinit(self: *Self) void {
        self.ctx.deinit();
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
        const code = self.ctx.bytecode.raw;

        // Verify we're not going beyond bytecode bounds.
        if (self.pc >= code.len) {
            return error.InvalidProgramCounter;
        }

        // Fetch and decode opcode byte
        const opcode_byte = code[self.pc];
        const opcode = try Opcode.fromByte(opcode_byte);

        // Ensure there are enough bytes for this opcode's immediates.
        const required_bytes = 1 + opcode.immediateBytes();
        if (self.pc + required_bytes > code.len) {
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

            .JUMP => {
                const new_pc = try handlers.opJump(&self.ctx.stack, &self.ctx.bytecode);
                self.pc = new_pc;
                return; // Don't increment PC - jump sets it directly
            },

            .JUMPI => {
                if (try handlers.opJumpi(&self.ctx.stack, &self.ctx.bytecode)) |new_pc| {
                    self.pc = new_pc;
                    return; // Don't increment PC - jump sets it directly
                }
                // Condition was false, don't jump - manually increment PC since JUMPI is a control flow opcode
                self.pc += 1;
            },

            .JUMPDEST => {
                // No-op at runtime - just a marker for valid jump destinations
            },

            .PC => try handlers.opPc(&self.ctx.stack, self.pc),

            .GAS => try handlers.opGas(&self.ctx.stack, &self.gas),

            .RETURN => {
                // Charge memory expansion gas
                try self.chargeMemoryExpansionDynamic(0, 1);

                // Execute handler
                const output = try handlers.opReturn(&self.ctx.stack, &self.ctx.memory);

                // Update memory cost tracker
                self.gas.updateMemoryCost(self.ctx.memory.len());

                // Copy output (memory may be freed)
                const owned_output = try self.allocator.dupe(u8, output);
                self.return_data = owned_output;
                self.is_halted = true;
            },

            .REVERT => { // Todo: enabled in EIP-140, validate
                // Charge memory expansion gas
                try self.chargeMemoryExpansionDynamic(0, 1);

                // Execute handler
                const output = try handlers.opRevert(&self.ctx.stack, &self.ctx.memory);

                // Update memory cost tracker
                self.gas.updateMemoryCost(self.ctx.memory.len());

                // Copy output (memory may be freed)
                const owned_output = try self.allocator.dupe(u8, output);
                self.return_data = owned_output;
                return error.Revert;
            },

            .INVALID => {
                // Equivalent to REVERT (since Byzantium fork) with 0,0 as stack parameters,
                // except that all the gas given to the current context is consumed.
                try self.gas.consume(self.gas.remaining());
                return error.InvalidOpcode;
            },

            // ================================================================
            // Stack Operations
            // ================================================================

            .POP => {
                _ = try self.ctx.stack.pop();
            },

            .PUSH0 => {
                // EIP-3855: PUSH0 pushes 0 without reading immediates
                if (!self.spec.has_push0) return error.InvalidOpcode;
                try self.ctx.stack.push(U256.ZERO);
            },

            // PUSH1-PUSH32: Push 1-32 bytes onto stack
            // With centralized PC management, we just read immediates and push
            .PUSH1, .PUSH2, .PUSH3, .PUSH4, .PUSH5, .PUSH6, .PUSH7, .PUSH8, .PUSH9, .PUSH10, .PUSH11, .PUSH12, .PUSH13, .PUSH14, .PUSH15, .PUSH16, .PUSH17, .PUSH18, .PUSH19, .PUSH20, .PUSH21, .PUSH22, .PUSH23, .PUSH24, .PUSH25, .PUSH26, .PUSH27, .PUSH28, .PUSH29, .PUSH30, .PUSH31, .PUSH32 => {
                // Read immediate bytes (bounds are already checked in step())
                const num_bytes = opcode.immediateBytes();
                const bytes = self.ctx.bytecode.raw[self.pc + 1 ..][0..num_bytes];

                const value = U256.fromBeBytesPadded(bytes);
                try self.ctx.stack.push(value);
            },

            // DUP1-DUP16: Duplicate Nth stack item (N=1 is top)
            // Opcode values are sequential: 0x80-0x8F
            .DUP1, .DUP2, .DUP3, .DUP4, .DUP5, .DUP6, .DUP7, .DUP8, .DUP9, .DUP10, .DUP11, .DUP12, .DUP13, .DUP14, .DUP15, .DUP16 => {
                const index = @intFromEnum(opcode) - @intFromEnum(Opcode.DUP1) + 1;
                try self.ctx.stack.dup(index);
            },

            // SWAP1-SWAP16: Swap top with Nth item (N=1 is second item)
            // Opcode values are sequential: 0x90-0x9F
            .SWAP1, .SWAP2, .SWAP3, .SWAP4, .SWAP5, .SWAP6, .SWAP7, .SWAP8, .SWAP9, .SWAP10, .SWAP11, .SWAP12, .SWAP13, .SWAP14, .SWAP15, .SWAP16 => {
                const index = @intFromEnum(opcode) - @intFromEnum(Opcode.SWAP1) + 1;
                try self.ctx.stack.swap(index);
            },

            // ================================================================
            // Arithmetic Operations
            // ================================================================

            .ADD => try handlers.opAdd(&self.ctx.stack),
            .MUL => try handlers.opMul(&self.ctx.stack),
            .SUB => try handlers.opSub(&self.ctx.stack),
            .DIV => try handlers.opDiv(&self.ctx.stack),
            .MOD => try handlers.opMod(&self.ctx.stack),
            .SDIV => try handlers.opSdiv(&self.ctx.stack),
            .SMOD => try handlers.opSmod(&self.ctx.stack),
            .ADDMOD => try handlers.opAddmod(&self.ctx.stack),
            .MULMOD => try handlers.opMulmod(&self.ctx.stack),

            .EXP => {
                // EXP has dynamic gas based on exponent byte length
                const exponent = try self.ctx.stack.peek(0);
                const exp_bytes: u8 = @intCast(exponent.byteLen());
                try self.gas.consume(cost_fns.expCost(self.spec, exp_bytes));

                try handlers.opExp(&self.ctx.stack);
            },

            .SIGNEXTEND => try handlers.opSignextend(&self.ctx.stack),

            // ================================================================
            // Comparison Operations
            // ================================================================

            .LT => try handlers.opLt(&self.ctx.stack),
            .GT => try handlers.opGt(&self.ctx.stack),
            .SLT => try handlers.opSlt(&self.ctx.stack),
            .SGT => try handlers.opSgt(&self.ctx.stack),
            .EQ => try handlers.opEq(&self.ctx.stack),
            .ISZERO => try handlers.opIszero(&self.ctx.stack),

            // ================================================================
            // Bitwise Operations
            // ================================================================

            .AND => try handlers.opAnd(&self.ctx.stack),
            .OR => try handlers.opOr(&self.ctx.stack),
            .XOR => try handlers.opXor(&self.ctx.stack),
            .NOT => try handlers.opNot(&self.ctx.stack),
            .BYTE => try handlers.opByte(&self.ctx.stack),
            .SHL => try handlers.opShl(&self.ctx.stack),
            .SHR => try handlers.opShr(&self.ctx.stack),
            .SAR => try handlers.opSar(&self.ctx.stack),

            // ================================================================
            // Cryptographic Operations
            // ================================================================

            .KECCAK256 => try handlers.opKeccak256(&self.ctx.stack, &self.ctx.memory),

            // ================================================================
            // Memory Operations
            // ================================================================

            .MLOAD => {
                try self.chargeMemoryExpansionFixed(0, 32);
                try handlers.opMload(&self.ctx.stack, &self.ctx.memory);
                self.gas.updateMemoryCost(self.ctx.memory.len());
            },

            .MSTORE => {
                try self.chargeMemoryExpansionFixed(0, 32);
                try handlers.opMstore(&self.ctx.stack, &self.ctx.memory);
                self.gas.updateMemoryCost(self.ctx.memory.len());
            },

            .MSTORE8 => {
                try self.chargeMemoryExpansionFixed(0, 1);
                try handlers.opMstore8(&self.ctx.stack, &self.ctx.memory);
                self.gas.updateMemoryCost(self.ctx.memory.len());
            },

            .MSIZE => try handlers.opMsize(&self.ctx.stack, &self.ctx.memory),

            .MCOPY => {
                const length_u256 = try self.ctx.stack.peek(2);
                const length = length_u256.toUsize() orelse return error.InvalidOffset;

                // Charge memory expansion for both source and dest regions.
                try self.chargeMemoryExpansionDualRegion(0, 1, 2);

                // Charge per-word copy cost (base VERYLOW=3 already charged)
                try self.gas.consume(cost_fns.mcopyDynamicCost(length));

                try handlers.opMcopy(&self.ctx.stack, &self.ctx.memory);

                self.gas.updateMemoryCost(self.ctx.memory.len());
            },

            // ================================================================
            // Storage Operations
            // ================================================================

            .SLOAD => try handlers.opSload(&self.ctx.stack),
            .SSTORE => try handlers.opSstore(&self.ctx.stack),
            .TLOAD => try handlers.opTload(&self.ctx.stack),
            .TSTORE => try handlers.opTstore(&self.ctx.stack),

            // ================================================================
            // System Operations
            // ================================================================

            .CREATE => try handlers.opCreate(&self.ctx.stack),
            .CREATE2 => try handlers.opCreate2(&self.ctx.stack),
            .CALL => try handlers.opCall(&self.ctx.stack),
            .CALLCODE => try handlers.opCallcode(&self.ctx.stack),
            .DELEGATECALL => try handlers.opDelegatecall(&self.ctx.stack),
            .STATICCALL => try handlers.opStaticcall(&self.ctx.stack),
            .SELFDESTRUCT => try handlers.opSelfdestruct(&self.ctx.stack),

            // ================================================================
            // Environmental Operations
            // ================================================================

            .ADDRESS => try handlers.opAddress(&self.ctx.stack),
            .BALANCE => try handlers.opBalance(&self.ctx.stack),
            .ORIGIN => try handlers.opOrigin(&self.ctx.stack),
            .CALLER => try handlers.opCaller(&self.ctx.stack),
            .CALLVALUE => try handlers.opCallvalue(&self.ctx.stack),
            .CALLDATALOAD => try handlers.opCalldataload(&self.ctx.stack),
            .CALLDATASIZE => try handlers.opCalldatasize(&self.ctx.stack),
            .CALLDATACOPY => try handlers.opCalldatacopy(&self.ctx.stack),
            .CODESIZE => try handlers.opCodesize(&self.ctx.stack),
            .CODECOPY => try handlers.opCodecopy(&self.ctx.stack),
            .GASPRICE => try handlers.opGasprice(&self.ctx.stack),
            .EXTCODESIZE => try handlers.opExtcodesize(&self.ctx.stack),
            .EXTCODECOPY => try handlers.opExtcodecopy(&self.ctx.stack),
            .RETURNDATASIZE => try handlers.opReturndatasize(&self.ctx.stack),
            .RETURNDATACOPY => try handlers.opReturndatacopy(&self.ctx.stack),
            .EXTCODEHASH => try handlers.opExtcodehash(&self.ctx.stack),
            .BLOCKHASH => try handlers.opBlockhash(&self.ctx.stack),
            .COINBASE => try handlers.opCoinbase(&self.ctx.stack),
            .TIMESTAMP => try handlers.opTimestamp(&self.ctx.stack),
            .NUMBER => try handlers.opNumber(&self.ctx.stack),
            .PREVRANDAO => try handlers.opPrevrandao(&self.ctx.stack),
            .GASLIMIT => try handlers.opGaslimit(&self.ctx.stack),
            .CHAINID => try handlers.opChainid(&self.ctx.stack),
            .SELFBALANCE => try handlers.opSelfbalance(&self.ctx.stack),
            .BASEFEE => try handlers.opBasefee(&self.ctx.stack),
            .BLOBHASH => try handlers.opBlobhash(&self.ctx.stack),
            .BLOBBASEFEE => try handlers.opBlobbasefee(&self.ctx.stack),

            // ================================================================
            // Logging Operations
            // ================================================================

            .LOG0 => try handlers.opLog0(&self.ctx.stack),
            .LOG1 => try handlers.opLog1(&self.ctx.stack),
            .LOG2 => try handlers.opLog2(&self.ctx.stack),
            .LOG3 => try handlers.opLog3(&self.ctx.stack),
            .LOG4 => try handlers.opLog4(&self.ctx.stack),
        }
    }

    /// Charge gas for memory expansion with fixed access size.
    ///
    /// This helper encapsulates the common pattern for memory operations
    /// with fixed-size accesses (MLOAD, MSTORE, MSTORE8).
    fn chargeMemoryExpansionFixed(
        self: *Self,
        offset_from_stack_top: usize,
        access_size: usize,
    ) !void {
        const offset_u256 = try self.ctx.stack.peek(offset_from_stack_top);
        const offset = offset_u256.toUsize() orelse return error.InvalidOffset;

        const old_size = self.ctx.memory.len();
        const new_size = offset +| access_size; // Saturating add for safety

        // Charge memory expansion gas
        const expansion_gas = self.gas.memoryExpansionCost(old_size, new_size);
        try self.gas.consume(expansion_gas);
    }

    /// Charge gas for memory expansion with dynamic access size.
    ///
    /// This helper encapsulates the common pattern for memory operations
    /// with dynamic-size accesses (RETURN, REVERT) where both offset and size
    /// are on the stack.
    fn chargeMemoryExpansionDynamic(
        self: *Self,
        offset_from_stack_top: usize,
        size_from_stack_top: usize,
    ) !void {
        const offset_u256 = try self.ctx.stack.peek(offset_from_stack_top);
        const size_u256 = try self.ctx.stack.peek(size_from_stack_top);

        const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
        const size = size_u256.toUsize() orelse return error.InvalidOffset;

        // Handle empty access case
        if (size == 0) {
            return;
        }

        const old_size = self.ctx.memory.len();
        const new_size = offset +| size; // Saturating add for safety

        // Charge memory expansion gas
        const expansion_gas = self.gas.memoryExpansionCost(old_size, new_size);
        try self.gas.consume(expansion_gas);
    }

    /// Charge gas for memory expansion with two regions (e.g., MCOPY source and dest).
    ///
    /// Calculates the maximum memory size needed for both regions and charges
    /// expansion cost accordingly. Handles zero-length case (no charge).
    fn chargeMemoryExpansionDualRegion(
        self: *Self,
        offset1_from_stack_top: usize,
        offset2_from_stack_top: usize,
        length_from_stack_top: usize,
    ) !void {
        const offset1_u256 = try self.ctx.stack.peek(offset1_from_stack_top);
        const offset2_u256 = try self.ctx.stack.peek(offset2_from_stack_top);
        const length_u256 = try self.ctx.stack.peek(length_from_stack_top);

        const offset1 = offset1_u256.toUsize() orelse return error.InvalidOffset;
        const offset2 = offset2_u256.toUsize() orelse return error.InvalidOffset;
        const length = length_u256.toUsize() orelse return error.InvalidOffset;

        // No expansion needed for zero-length
        if (length == 0) return;

        const old_size = self.ctx.memory.len();
        const end1 = offset1 +| length; // Saturating add
        const end2 = offset2 +| length;
        const max_end = @max(end1, end2);

        const expansion_gas = self.gas.memoryExpansionCost(old_size, max_end);
        try self.gas.consume(expansion_gas);
    }

    /// Convert a Zig error to an ExecutionStatus.
    ///
    /// IMPORTANT: This function must handle all errors explicitly.
    /// Do NOT add an `else` catch-all case. Each error from the Error
    /// union must be consciously mapped to an ExecutionStatus to ensure
    /// proper error handling and prevent unexpected behavior.
    fn handleError(self: *Self, err: Error) InterpreterResult {
        const status: ExecutionStatus = switch (err) {
            error.StackOverflow => .STACK_OVERFLOW,
            error.StackUnderflow => .STACK_UNDERFLOW,
            error.OutOfGas => .OUT_OF_GAS,
            error.OutOfMemory => .OUT_OF_GAS,
            error.InvalidOffset, error.IntegerOverflow => .INVALID_OPCODE,
            error.InvalidOpcode, error.UnimplementedOpcode, error.InvalidBytecode => .INVALID_OPCODE,
            error.InvalidProgramCounter => .INVALID_PC,
            error.InvalidJump => .INVALID_JUMP,
            error.Revert => .REVERT,
        };

        return InterpreterResult{
            .status = status,
            .gas_used = self.gas.used,
            .gas_refund = self.gas.finalRefund(),
            .return_data = self.return_data,
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
