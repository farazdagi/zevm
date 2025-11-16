//! Common test helpers for interpreter tests

const std = @import("std");
const zevm = @import("zevm");

const Interpreter = zevm.interpreter.Interpreter;
const ExecutionStatus = zevm.interpreter.ExecutionStatus;
const Spec = zevm.hardfork.Spec;
const Hardfork = zevm.hardfork.Hardfork;
const U256 = zevm.primitives.U256;
const Address = zevm.primitives.Address;
const B256 = zevm.primitives.B256;
const Env = zevm.context.Env;
const BlockEnv = zevm.context.BlockEnv;
const TxEnv = zevm.context.TxEnv;
const MockHost = zevm.host.MockHost;
const Host = zevm.host.Host;

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

/// Create test environment with optional customization
pub fn createTestEnv(opts: struct {
    block_number: u64 = 1,
    timestamp: u64 = 0,
    caller: Address = Address.zero(),
    value: U256 = U256.ZERO,
}) Env {
    return .{
        .block = BlockEnv{
            .number = opts.block_number,
            .coinbase = Address.zero(),
            .timestamp = opts.timestamp,
            .gas_limit = 30_000_000,
            .basefee = U256.ZERO,
            .prevrandao = B256.zero(),
        },
        .tx = TxEnv{
            .caller = opts.caller,
            .origin = opts.caller,
            .gas_price = U256.fromU64(1),
            .value = opts.value,
            .data = &[_]u8{},
        },
    };
}

/// Create test interpreter with mock host
pub fn createTestInterpreter(
    allocator: std.mem.Allocator,
    bytecode: []const u8,
    contract_address: Address,
    fork: Hardfork,
    gas_limit: u64,
    env: *const Env,
    mock_host: *MockHost,
) !Interpreter {
    const spec = Spec.forFork(fork);
    const host = mock_host.host();
    return try Interpreter.init(allocator, bytecode, contract_address, spec, gas_limit, env, host);
}

/// Create test interpreter with default contract address (zero)
pub fn createTestInterpreterDefault(
    allocator: std.mem.Allocator,
    bytecode: []const u8,
    fork: Hardfork,
    gas_limit: u64,
    env: *const Env,
    mock_host: *MockHost,
) !Interpreter {
    return createTestInterpreter(allocator, bytecode, Address.zero(), fork, gas_limit, env, mock_host);
}

/// Run a series of opcode tests using table-based test cases.
pub fn runOpcodeTests(allocator: std.mem.Allocator, test_cases: []const TestCase) !void {
    // Create default env and mock host for all tests
    const env = createTestEnv(.{});
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    for (test_cases) |tc| {
        // Init interpreter with provided bytecode and spec.
        var interpreter = try createTestInterpreter(
            allocator,
            tc.bytecode,
            Address.zero(),
            tc.spec.fork,
            10000,
            &env,
            &mock,
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

        try expect(interpreter.ctx.stack.eql(&expected_stack));
    }
}
