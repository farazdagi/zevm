//! Bytecode Interpreter
//!
//! Executes EVM bytecode using a fetch-decode-execute loop.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Stack = @import("stack.zig").Stack;
const Memory = @import("memory.zig").Memory;
const Gas = @import("../gas/accounting.zig").Gas;
const Spec = @import("../hardfork.zig").Spec;
const Opcode = @import("opcode.zig").Opcode;
const U256 = @import("../primitives/big.zig").U256;
const Address = @import("../primitives/address.zig").Address;
const Bytecode = @import("bytecode.zig").Bytecode;
const AnalyzedBytecode = @import("bytecode.zig").AnalyzedBytecode;
const JumpTable = @import("JumpTable.zig");
const InstructionTable = @import("InstructionTable.zig");
const Env = @import("../context.zig").Env;
const Host = @import("../host/Host.zig");
const CallExecutor = @import("../call_types.zig").CallExecutor;
const CallInputs = @import("../call_types.zig").CallInputs;
const CallResult = @import("../call_types.zig").CallResult;
const Contract = @import("../Contract.zig");
const AccessListAccessor = @import("../lib.zig").AccessListAccessor;

// Instruction handlers
const handlers = @import("handlers/mod.zig");

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

    /// Call depth exceeded (> 1024 frames)
    CALL_DEPTH_EXCEEDED,
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

/// Configuration for interpreter execution.
///
/// Contains the external context needed for execution/interpretation.
pub const InterpreterConfig = struct {
    /// Spec (fork-specific rules and costs).
    spec: Spec,

    /// Gas limit for this execution.
    gas_limit: u64,

    /// Environmental context (block and transaction info).
    env: *const Env,

    /// Host interface for blockchain state access.
    host: Host,

    /// Return data from last nested call (EIP-211).
    /// Points to EVM-owned buffer, updated after CALL/CREATE operations.
    return_data_buffer: *[]const u8,

    /// Whether state modifications are forbidden (STATICCALL context).
    is_static: bool,

    /// Interface for nested calls (CALL/DELEGATECALL/STATICCALL/CREATE/CREATE2).
    call_executor: CallExecutor,

    /// Access list accessor for EIP-2929 cold/warm tracking.
    access_list: AccessListAccessor,
};

/// Call-scoped execution context.
///
/// Contains the state that is local to a single execution context (call frame).
/// This includes the contract being executed (code + address), the operand stack, and memory.
/// When implementing CALL/DELEGATECALL/STATICCALL operations, each nested call will have its
/// own context.
pub const CallContext = struct {
    /// The contract being executed.
    contract: Contract,

    /// Operand stack.
    stack: Stack,

    /// Call memory.
    memory: Memory,

    /// Initialize a new interpreter context.
    ///
    /// Parameters:
    /// - allocator: Memory allocator for stack and memory.
    /// - analyzed: Pre-analyzed bytecode (ownership transferred).
    /// - address: The context address (where storage operations apply).
    /// - caller: The caller of this frame (msg.sender).
    /// - value: The value sent with this call (msg.value).
    ///
    /// The caller must resolve EIP-7702 delegation before calling this function.
    /// This is enforced at the type level by requiring AnalyzedBytecode.
    pub fn init(
        allocator: Allocator,
        analyzed: AnalyzedBytecode,
        address: Address,
        caller: Address,
        value: U256,
    ) !CallContext {
        // Create stack and memory.
        var stack = try Stack.init(allocator);
        errdefer stack.deinit();

        var memory = try Memory.init(allocator);
        errdefer memory.deinit();

        return CallContext{
            .contract = .{
                .bytecode = analyzed,
                .address = address,
                .caller = caller,
                .value = value,
                .allocator = allocator,
            },
            .stack = stack,
            .memory = memory,
        };
    }

    /// Clean up allocated resources.
    pub fn deinit(self: *CallContext) void {
        self.stack.deinit();
        self.memory.deinit();
        self.contract.deinit();
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
        StateWriteInStaticCall,
    };

    /// Call-scoped execution context (stack, memory, bytecode).
    ctx: CallContext,

    /// Program counter (index into bytecode).
    pc: usize,

    /// Gas accounting.
    gas: Gas,

    /// Spec (fork-specific rules and costs).
    spec: Spec,

    /// Instruction dispatch table (configured for this fork).
    table: *const InstructionTable,

    /// Allocator for dynamic memory.
    allocator: Allocator,

    /// Return data (set by RETURN or REVERT).
    return_data: ?[]const u8,

    /// Whether execution has halted.
    is_halted: bool,

    /// Environmental context (block and transaction info).
    env: *const Env,

    /// Host interface for blockchain state access.
    host: Host,

    /// Return data from last nested call (EIP-211).
    /// Points to EVM-owned buffer, updated after CALL/CREATE operations.
    return_data_buffer: *[]const u8,

    /// Whether state modifications are forbidden (STATICCALL context).
    is_static: bool,

    /// Interface for nested calls (CALL/DELEGATECALL/STATICCALL/CREATE/CREATE2).
    call_executor: CallExecutor,

    /// Access list accessor for EIP-2929 cold/warm tracking.
    access_list: AccessListAccessor,

    const Self = @This();

    /// Initialize interpreter with pre-created call context.
    pub fn init(
        allocator: Allocator,
        ctx: CallContext,
        config: InterpreterConfig,
    ) Self {
        return Self{
            .allocator = allocator,
            .ctx = ctx,
            .pc = 0,
            .gas = Gas.init(config.gas_limit, config.spec),
            .spec = config.spec,
            .table = config.spec.instructionTable(),
            .is_halted = false,
            .return_data = null,
            .env = config.env,
            .host = config.host,
            .return_data_buffer = config.return_data_buffer,
            .is_static = config.is_static,
            .call_executor = config.call_executor,
            .access_list = config.access_list,
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
        const code = self.ctx.contract.bytecode.raw;

        // Verify we're not going beyond bytecode bounds.
        if (self.pc >= code.len) {
            return error.InvalidProgramCounter;
        }

        // Fetch opcode byte.
        const opcode = Opcode.fromByte(code[self.pc]);

        // Validate immediate bytes (currently, only PUSH operations have non-zero immediate bytes).
        if (self.pc + opcode.immediateBytes() + 1 > code.len) {
            return error.InvalidProgramCounter;
        }

        // Look up instruction info from jump table.
        const instruction = self.table.get(@intFromEnum(opcode));

        // Charge base gas cost for a given opcode in a given spec.
        // CRITICAL: Gas MUST be charged before execution to prevent side effects on out of gas.
        const base_gas = self.spec.gasCost(@intFromEnum(opcode));
        try self.gas.consume(base_gas);

        // Charge dynamic gas if present (e.g., EXP, memory expansion).
        if (instruction.dynamicGasCost) |dynamicGasCost| {
            const dynamic_gas = try dynamicGasCost(self);
            try self.gas.consume(dynamic_gas);
        }

        // Save old PC to detect changes (needed for JUMPI).
        const old_pc = self.pc;

        // Execute instruction handler.
        try instruction.execute(self);

        // Update memory cost tracker for operations that touch memory.
        // This must happen after handler execution, when memory size is finalized.
        if (opcode.needsMemoryCostUpdate()) {
            self.gas.updateMemoryCost(self.ctx.memory.len());
        }

        // Handle PC increment:
        //
        // If halted (STOP, RETURN, INVALID), no increment.
        // If is_control_flow (JUMP, RETURN, REVERT, STOP, INVALID), no increment.
        // If PC changed (JUMPI took the jump), no increment.
        // Otherwise, increment by 1 + immediate bytes.
        if (!self.is_halted and !instruction.is_control_flow and self.pc == old_pc) {
            self.pc += 1 + opcode.immediateBytes();
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
            error.StateWriteInStaticCall => .REVERT,
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
