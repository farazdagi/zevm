const std = @import("std");

pub const stack = @import("stack.zig");
pub const memory = @import("memory.zig");
pub const gas = @import("../gas/mod.zig");
pub const hardfork = @import("../hardfork.zig");
pub const opcode = @import("opcode.zig");
pub const interpreter = @import("interpreter.zig");
pub const handlers = @import("handlers/mod.zig");
pub const bytecode = @import("bytecode.zig");

// Re-exports
pub const Stack = stack.Stack;
pub const Memory = memory.Memory;
pub const Gas = gas.Gas;
pub const Hardfork = hardfork.Hardfork;
pub const Spec = hardfork.Spec;
pub const Opcode = opcode.Opcode;
pub const Interpreter = interpreter.Interpreter;
pub const ExecutionStatus = interpreter.ExecutionStatus;
pub const InterpreterResult = interpreter.InterpreterResult;
pub const Bytecode = bytecode.Bytecode;
pub const AnalyzedBytecode = bytecode.AnalyzedBytecode;
pub const Eip7702Bytecode = bytecode.Eip7702Bytecode;
pub const InstructionTable = @import("InstructionTable.zig");

test {
    std.testing.refAllDecls(@This());
    _ = handlers;
    _ = stack;
    _ = memory;
    _ = gas;
    _ = opcode;
    _ = interpreter;
    _ = bytecode;
}
