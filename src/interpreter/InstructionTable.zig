//! Jump table mapping opcodes (0x00-0xFF) to instruction information.
//!
//! This is the core dispatch structure. Each entry corresponds to one opcode value.
//! Invalid/unimplemented opcodes map to a stub handler that returns error.InvalidOpcode.

const Interpreter = @import("interpreter.zig").Interpreter;
const hardfork = @import("../hardfork.zig");
const Spec = hardfork.Spec;

const InstructionTable = @This();

/// Function pointer type for instruction handlers.
const HandlerFn = *const fn (interp: *Interpreter) Interpreter.Error!void;

/// Function pointer type for dynamic gas calculation.
///
/// Dynamic gas functions compute variable gas costs based on operand values
/// (e.g., EXP cost depends on exponent byte length, memory operations depend
/// on expansion). They are called BEFORE the handler executes.
///
/// Returns the additional gas to charge beyond the base cost.
/// Null means no dynamic gas (only base cost applies).
const DynamicGasFn = ?*const fn (interp: *Interpreter) Interpreter.Error!u64;

/// Metadata and dispatch information for a single instruction.
const InstructionInfo = struct {
    /// Handler function to execute the instruction.
    execute: *const fn (interp: *Interpreter) Interpreter.Error!void,

    /// Optional dynamic gas calculation function.
    dynamicGasCost: DynamicGasFn = null,

    /// Whether this instruction performs control flow (affects PC directly).
    ///
    /// Control flow instructions: JUMP, JUMPI (conditional), RETURN, REVERT, STOP, INVALID.
    ///
    /// Note: JUMPI is special - it's NOT marked as is_control_flow, but step() detects PC changes
    /// to handle it correctly.
    is_control_flow: bool = false,
};

/// Table of 256 instruction entries (one per possible opcode byte).
table: [256]InstructionInfo,

/// Spec this table is configured for
spec: Spec,

/// Pre-computed instruction tables for each fork.
pub const FRONTIER: InstructionTable = computeHandlersForSpec(hardfork.FRONTIER);
pub const HOMESTEAD: InstructionTable = computeHandlersForSpec(hardfork.HOMESTEAD);
pub const TANGERINE: InstructionTable = computeHandlersForSpec(hardfork.TANGERINE);
pub const SPURIOUS_DRAGON: InstructionTable = computeHandlersForSpec(hardfork.SPURIOUS_DRAGON);
pub const BYZANTIUM: InstructionTable = computeHandlersForSpec(hardfork.BYZANTIUM);
pub const CONSTANTINOPLE: InstructionTable = computeHandlersForSpec(hardfork.CONSTANTINOPLE);
pub const PETERSBURG: InstructionTable = computeHandlersForSpec(hardfork.PETERSBURG);
pub const ISTANBUL: InstructionTable = computeHandlersForSpec(hardfork.ISTANBUL);
pub const MUIR_GLACIER: InstructionTable = computeHandlersForSpec(hardfork.MUIR_GLACIER);
pub const BERLIN: InstructionTable = computeHandlersForSpec(hardfork.BERLIN);
pub const LONDON: InstructionTable = computeHandlersForSpec(hardfork.LONDON);
pub const ARROW_GLACIER: InstructionTable = computeHandlersForSpec(hardfork.ARROW_GLACIER);
pub const GRAY_GLACIER: InstructionTable = computeHandlersForSpec(hardfork.GRAY_GLACIER);
pub const MERGE: InstructionTable = computeHandlersForSpec(hardfork.MERGE);
pub const SHANGHAI: InstructionTable = computeHandlersForSpec(hardfork.SHANGHAI);
pub const CANCUN: InstructionTable = computeHandlersForSpec(hardfork.CANCUN);
pub const PRAGUE: InstructionTable = computeHandlersForSpec(hardfork.PRAGUE);

/// Get pre-computed instruction table for a specific fork.
pub fn forFork(fork: hardfork.Hardfork) *const InstructionTable {
    return switch (fork) {
        .FRONTIER => &FRONTIER,
        .FRONTIER_THAWING => &FRONTIER,
        .HOMESTEAD => &HOMESTEAD,
        .DAO_FORK => &HOMESTEAD,
        .TANGERINE => &TANGERINE,
        .SPURIOUS_DRAGON => &SPURIOUS_DRAGON,
        .BYZANTIUM => &BYZANTIUM,
        .CONSTANTINOPLE => &CONSTANTINOPLE,
        .PETERSBURG => &PETERSBURG,
        .ISTANBUL => &ISTANBUL,
        .MUIR_GLACIER => &MUIR_GLACIER,
        .BERLIN => &BERLIN,
        .LONDON => &LONDON,
        .ARROW_GLACIER => &ARROW_GLACIER,
        .GRAY_GLACIER => &GRAY_GLACIER,
        .MERGE => &MERGE,
        .SHANGHAI => &SHANGHAI,
        .CANCUN => &CANCUN,
        .PRAGUE => &PRAGUE,
        .OSAKA => &PRAGUE, // Use Prague for future Osaka
    };
}

/// Get instruction info for an opcode.
pub inline fn get(self: *const InstructionTable, opcode: u8) InstructionInfo {
    return self.table[opcode];
}

/// Handler for unimplemented opcodes.
///
/// This is used as the default handler for opcodes that are not valid in a particular hardfork.
pub fn unimplementedOpcodeHandler(interp: *Interpreter) Interpreter.Error!void {
    _ = interp;
    return error.UnimplementedOpcode;
}

/// Stub handler for INVALID (0xFE).
///
/// Consumes all remaining gas and returns error.InvalidOpcode.
pub fn opInvalid(interp: *Interpreter) Interpreter.Error!void {
    // Consume all remaining gas
    try interp.gas.consume(interp.gas.remaining());
    return error.InvalidOpcode;
}

/// Handler for STOP (0x00).
///
/// Halts execution successfully with no return data.
pub fn opStop(interp: *Interpreter) Interpreter.Error!void {
    interp.is_halted = true;
}

/// Handler for JUMPDEST (0x5B).
///
/// This is a no-op at runtime - just marks a valid jump destination.
pub fn opJumpdest(interp: *Interpreter) Interpreter.Error!void {
    _ = interp;
    // No-op: JUMPDEST is just a marker
}

/// Recursively compute instruction handlers for a specific fork.
///
/// This builds handlers incrementally: base fork handlers + this fork's updates.
/// For Frontier (base_fork = null), initializes empty table.
/// For other forks, gets base fork handlers and applies this fork's updateHandlers().
fn computeHandlersForSpec(comptime spec: Spec) InstructionTable {
    @setEvalBranchQuota(10000);

    var table: [256]InstructionInfo = undefined;

    // Initialize all entries to invalid handler.
    for (&table) |*entry| {
        entry.* = InstructionInfo{
            .execute = unimplementedOpcodeHandler,
            .dynamicGasCost = null,
            .is_control_flow = false,
        };
    }

    var result = InstructionTable{
        .table = table,
        .spec = spec,
    };

    // For Frontier the table already initialized to invalid handlers.
    // For other forks replace it with the base fork's recursively computed table.
    if (spec.base_fork) |base| {
        const base_spec = Spec.forFork(base);
        result = computeHandlersForSpec(base_spec);
        // Update spec to current fork (preserve accumulated handlers)
        result.spec = spec;
    }

    // Apply this fork's handler updates (if any).
    if (spec.updateHandlers) |updateFn| {
        updateFn(&result);
    }

    return result;
}
