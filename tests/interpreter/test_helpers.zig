//! Common test helpers for interpreter tests

const std = @import("std");
const zevm = @import("zevm");

const Interpreter = zevm.interpreter.Interpreter;
const ExecutionStatus = zevm.interpreter.ExecutionStatus;
const Spec = zevm.hardfork.Spec;
const U256 = zevm.primitives.U256;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

/// Test case structure for table-based opcode tests
pub const TestCase = struct {
    /// Descriptive name for the test case
    name: []const u8,
    /// Bytecode to execute (including STOP opcode)
    bytecode: []const u8,
    /// Expected stack state after execution (bottom to top)
    expected_stack: []const U256,
    /// Expected gas consumption
    expected_gas: u64,
    /// Spec to use (defaults to BERLIN)
    spec: Spec = Spec.forFork(.BERLIN),
};

/// Run a series of opcode tests using table-based test cases.
pub fn runOpcodeTests(allocator: std.mem.Allocator, test_cases: []const TestCase) !void {
    for (test_cases) |tc| {
        // Init interpreter with provided bytecode and spec.
        var interpreter = try Interpreter.init(
            allocator,
            tc.bytecode,
            tc.spec,
            10000,
        );
        defer interpreter.deinit();

        // Execute.
        const result = try interpreter.run();
        try expectEqual(ExecutionStatus.SUCCESS, result.status);
        try expectEqual(tc.expected_gas, result.gas_used);

        // Build expected stack for comparison.
        var expected_stack = try zevm.interpreter.Stack.init(allocator);
        defer expected_stack.deinit();
        for (tc.expected_stack) |value| {
            try expected_stack.push(value);
        }

        try expect(interpreter.stack.eql(&expected_stack));
    }
}
