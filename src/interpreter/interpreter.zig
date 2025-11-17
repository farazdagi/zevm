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
const InstructionTable = @import("InstructionTable.zig");
const Env = @import("../context.zig").Env;
const Host = @import("../host/Host.zig");
const Evm = @import("../evm.zig").Evm;

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

/// Contract represents the bytecode being executed and its address.
pub const Contract = struct {
    /// The bytecode being executed (with JUMPDEST analysis).
    bytecode: AnalyzedBytecode,

    /// The address of this contract.
    ///
    /// This is the address where the code resides.
    /// For regular calls, this is the callee's address.
    /// For DELEGATECALL, this is the caller's address (code borrowed from callee).
    address: Address,

    /// Allocator for cleanup.
    allocator: Allocator,

    /// Clean up allocated resources.
    pub fn deinit(self: *Contract) void {
        self.bytecode.deinit();
    }
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
    /// Takes ownership of raw_bytecode and analyzes it internally.
    ///
    /// If the bytecode is EIP-7702 delegation bytecode, this will return an error - the caller
    /// (EVM) must resolve delegation before creating the context.
    pub fn init(allocator: Allocator, raw_bytecode: []u8, address: Address) !CallContext {
        var bytecode = try Bytecode.analyze(allocator, raw_bytecode);

        const analyzed = switch (bytecode) {
            .analyzed => |b| b,
            .eip7702 => {
                // Caller must resolve delegation first
                bytecode.deinit();
                return error.InvalidBytecode;
            },
        };

        // Create stack and memory
        var stack = try Stack.init(allocator);
        errdefer stack.deinit();

        var memory = try Memory.init(allocator);
        errdefer memory.deinit();

        return CallContext{
            .contract = .{
                .bytecode = analyzed,
                .address = address,
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
    table: InstructionTable,

    /// Allocator for dynamic memory.
    allocator: Allocator,

    /// Return data (set by RETURN or REVERT).
    return_data: ?[]const u8,

    /// Return data buffer from the last sub-call.
    ///
    /// Used by RETURNDATASIZE and RETURNDATACOPY opcodes (EIP-211, Byzantium).
    /// Updated after each sub-call (CALL, DELEGATECALL, STATICCALL, CREATE, CREATE2).
    return_data_buffer: []const u8,

    /// Whether execution has halted.
    is_halted: bool,

    /// Environmental context (block and transaction info).
    env: *const Env,

    /// Host interface for blockchain state access.
    host: Host,

    const Self = @This();

    /// Initialize interpreter with pre-created call context.
    pub fn init(
        allocator: Allocator,
        ctx: CallContext,
        spec: Spec,
        gas_limit: u64,
        env: *const Env,
        host: Host,
    ) Self {
        return Self{
            .allocator = allocator,
            .ctx = ctx,
            .pc = 0,
            .gas = Gas.init(gas_limit, spec),
            .spec = spec,
            .table = spec.instructionTable(),
            .is_halted = false,
            .return_data = null,
            .return_data_buffer = &[_]u8{}, // Empty initially, updated after sub-calls
            .env = env,
            .host = host,
        };
    }

    /// Clean up allocated resources.
    pub fn deinit(self: *Self) void {
        self.ctx.deinit();
        // return_data is owned by the caller after extracting from result
    }

    /// Execute bytecode until halted or error.
    ///
    /// The `evm` parameter provides access to the EVM layer for nested calls
    /// (CALL, DELEGATECALL, STATICCALL) and contract creation (CREATE, CREATE2).
    ///
    /// Returns the execution result including status, gas used, and return data.
    pub fn run(self: *Self, evm: *Evm) !InterpreterResult {
        _ = evm; // Will be used by call/create handlers in future tasks

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
