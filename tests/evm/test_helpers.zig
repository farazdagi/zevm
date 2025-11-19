//! Shared test infrastructure for EVM integration tests.
//!
//! Provides common addresses, bytecode builders, and test utilities.

const std = @import("std");
const zevm = @import("zevm");

pub const Evm = zevm.Evm;
pub const CallInputs = zevm.CallInputs;
pub const CallKind = zevm.CallKind;
pub const ExecutionStatus = zevm.interpreter.ExecutionStatus;
pub const Address = zevm.primitives.Address;
pub const U256 = zevm.primitives.U256;
pub const Env = zevm.context.Env;
pub const Spec = zevm.hardfork.Spec;
pub const MockHost = zevm.host.MockHost;

pub const expect = std.testing.expect;
pub const expectEqual = std.testing.expectEqual;

// Standard Test Addresses
pub const CALLER = Address.init([_]u8{0} ** 12 ++ [_]u8{ 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11 });
pub const TARGET = Address.init([_]u8{0} ** 12 ++ [_]u8{ 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22 });
pub const TARGET2 = Address.init([_]u8{0} ** 12 ++ [_]u8{ 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x33 });
pub const ORIGIN = Address.init([_]u8{0} ** 12 ++ [_]u8{ 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA });
pub const SIMPLE_CALLER = Address.init([_]u8{0} ** 19 ++ [_]u8{0x01});
pub const SIMPLE_TARGET = Address.init([_]u8{0} ** 19 ++ [_]u8{0x02});

/// Create bytecode that just STOPs (empty execution).
pub fn createStopContract() []const u8 {
    return &[_]u8{0x00}; // STOP
}

/// Create bytecode that pushes a value and returns it as 32-byte word.
/// Bytecode: PUSH1 value, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
pub fn createValueReturner(comptime value: u8) []const u8 {
    return &[_]u8{
        0x60, value, // PUSH1 value
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

/// Create bytecode that returns 4 bytes: 0xAA, 0xBB, 0xCC, 0xDD.
pub fn createPatternReturner() []const u8 {
    return &[_]u8{
        0x63, 0xAA, 0xBB, 0xCC, 0xDD, // PUSH4 0xAABBCCDD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE (stores as 32-byte word, value at end)
        0x60, 0x04, // PUSH1 4 (return size)
        0x60, 0x1C, // PUSH1 28 (return offset, to get last 4 bytes)
        0xF3, // RETURN
    };
}

/// Create bytecode that returns CALLER address as 32-byte word.
/// Bytecode: CALLER, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
pub fn createCallerReturner() []const u8 {
    return &[_]u8{
        0x33, // CALLER
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

/// Create bytecode that returns CALLVALUE.
/// Bytecode: CALLVALUE, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
pub fn createCallvalueReturner() []const u8 {
    return &[_]u8{
        0x34, // CALLVALUE
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

/// Create bytecode that returns ADDRESS (current contract address) as 32-byte word.
/// Bytecode: ADDRESS, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
pub fn createAddressReturner() []const u8 {
    return &[_]u8{
        0x30, // ADDRESS
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

/// Create bytecode that returns ORIGIN as 32-byte word.
/// Bytecode: ORIGIN, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
pub fn createOriginReturner() []const u8 {
    return &[_]u8{
        0x32, // ORIGIN
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

/// Create bytecode that returns CODESIZE.
/// Bytecode: CODESIZE, PUSH1 0, MSTORE, PUSH1 32, PUSH1 0, RETURN
pub fn createCodesizeReturner() []const u8 {
    return &[_]u8{
        0x38, // CODESIZE
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };
}

/// Create bytecode that REVERTs with no data.
pub fn createRevertContract() []const u8 {
    return &[_]u8{
        0x60, 0x00, // PUSH1 0 (size)
        0x60, 0x00, // PUSH1 0 (offset)
        0xFD, // REVERT
    };
}

/// Create bytecode that REVERTs with data: 0xDEADBEEF.
pub fn createRevertWithData() []const u8 {
    return &[_]u8{
        0x63, 0xDE, 0xAD, 0xBE, 0xEF, // PUSH4 0xDEADBEEF
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x04, // PUSH1 4
        0x60, 0x1C, // PUSH1 28
        0xFD, // REVERT
    };
}

/// Create bytecode that runs out of gas (infinite loop).
pub fn createOogContract() []const u8 {
    return &[_]u8{
        0x5B, // JUMPDEST
        0x60, 0x00, // PUSH1 0
        0x56, // JUMP
    };
}

/// Create bytecode with invalid opcode (0xFE).
pub fn createInvalidOpcodeContract() []const u8 {
    return &[_]u8{0xFE}; // INVALID
}

/// Create bytecode that causes stack underflow (POP with empty stack).
pub fn createStackUnderflowContract() []const u8 {
    return &[_]u8{0x50}; // POP (empty stack)
}

/// Create bytecode that jumps to invalid destination.
pub fn createInvalidJumpContract() []const u8 {
    return &[_]u8{
        0x60, 0xFF, // PUSH1 0xFF (invalid destination)
        0x56, // JUMP
    };
}

/// Create bytecode that emits LOG0 (state-modifying, fails in static).
pub fn createLogContract() []const u8 {
    return &[_]u8{
        0x60, 0x00, // PUSH1 0 (size)
        0x60, 0x00, // PUSH1 0 (offset)
        0xA0, // LOG0
        0x00, // STOP
    };
}

/// Create bytecode that performs computation.
/// PUSH1 10, PUSH1 20, ADD, POP, STOP (costs: 3+3+3+2+0 = 11 gas).
pub fn createComputeContract() []const u8 {
    return &[_]u8{
        0x60, 0x0A, // PUSH1 10
        0x60, 0x14, // PUSH1 20
        0x01, // ADD
        0x50, // POP
        0x00, // STOP
    };
}

/// Create bytecode: PUSH1 value, POP, STOP (5 gas total).
pub fn createSimpleComputeContract(comptime value: u8) []const u8 {
    return &[_]u8{
        0x60, value, // PUSH1 value
        0x50, // POP
        0x00, // STOP
    };
}

/// Extract address from 32-byte return data (last 20 bytes).
pub fn extractAddressFromReturn(output: []const u8) Address {
    if (output.len < 32) return Address.zero();
    var bytes: [20]u8 = undefined;
    @memcpy(&bytes, output[12..32]);
    return Address.init(bytes);
}

/// Extract u64 from last 8 bytes of 32-byte return data.
pub fn extractU64FromReturn(output: []const u8) u64 {
    var value: u64 = 0;
    for (output[24..32]) |byte| {
        value = (value << 8) | byte;
    }
    return value;
}

/// Extract single byte from end of 32-byte word.
pub fn extractByteFromReturn(output: []const u8) u8 {
    return output[31];
}

/// Universal test case for EVM call tests.
pub const TestCase = struct {
    // Call configuration.
    kind: CallKind = .CALL,
    caller: Address = SIMPLE_CALLER,
    target: Address = SIMPLE_TARGET,
    value: u64 = 0,
    gas_limit: u64 = 100000,
    transfer_value: bool = false,
    input: []const u8 = &[_]u8{},

    // Target contract bytecode (null = no code set).
    target_code: ?[]const u8 = null,

    // Initial state setup.
    caller_balance: ?u64 = null,
    target_balance: ?u64 = null,
    initial_depth: u16 = 0,
    is_static: bool = false,

    // Expected results.
    expected_status: ExecutionStatus = .SUCCESS,
    expected_output_len: ?usize = null,
    expected_output_byte: ?u8 = null, // Check output[31].
    expected_output_pattern: ?[]const u8 = null, // Check exact output.

    // Balance assertions (after call).
    expected_caller_balance: ?u64 = null,
    expected_target_balance: ?u64 = null,

    // Gas assertions.
    expected_gas_used: ?u64 = null,
    expect_gas_used_gt: ?u64 = null,
    expect_gas_used_lt: ?u64 = null,

    // Context assertions (for return data that contains context).
    expected_caller_in_output: ?Address = null,
    expected_address_in_output: ?Address = null,
    expected_value_in_output: ?u64 = null,

    // Depth assertions.
    expected_final_depth: ?u16 = null,

    // Return data buffer assertions.
    expected_return_buffer_len: ?usize = null,
    expected_return_buffer_byte: ?u8 = null, // Check return_data_buffer[31].
};

/// Run a single test case.
pub fn runTestCase(tc: TestCase) !void {
    const allocator = std.testing.allocator;
    var env = Env.default();
    env.tx.origin = ORIGIN;

    var mock = MockHost.init(allocator);
    defer mock.deinit();

    const spec = Spec.forFork(.CANCUN);
    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    // Setup initial state.
    if (tc.target_code) |code| {
        try mock.setCode(tc.target, code);
    }
    if (tc.caller_balance) |bal| {
        try mock.setBalance(tc.caller, U256.fromU64(bal));
    }
    if (tc.target_balance) |bal| {
        try mock.setBalance(tc.target, U256.fromU64(bal));
    }
    evm.depth = tc.initial_depth;
    evm.is_static = tc.is_static;

    // Execute call.
    const inputs = CallInputs{
        .kind = tc.kind,
        .target = tc.target,
        .caller = tc.caller,
        .value = U256.fromU64(tc.value),
        .input = tc.input,
        .gas_limit = tc.gas_limit,
        .transfer_value = tc.transfer_value,
    };

    const result = try evm.call(inputs);

    // Verify status.
    try expectEqual(tc.expected_status, result.status);

    // Verify output.
    if (tc.expected_output_len) |len| {
        try expectEqual(len, result.output.len);
    }
    if (tc.expected_output_byte) |byte| {
        try expect(result.output.len >= 32);
        try expectEqual(byte, result.output[31]);
    }
    if (tc.expected_output_pattern) |pattern| {
        try expectEqual(pattern.len, result.output.len);
        for (pattern, 0..) |byte, i| {
            try expectEqual(byte, result.output[i]);
        }
    }

    // Verify balances.
    const h = mock.host();
    if (tc.expected_caller_balance) |bal| {
        try expect(h.balance(tc.caller).eql(U256.fromU64(bal)));
    }
    if (tc.expected_target_balance) |bal| {
        try expect(h.balance(tc.target).eql(U256.fromU64(bal)));
    }

    // Verify gas.
    if (tc.expected_gas_used) |gas| {
        try expectEqual(gas, result.gas_used);
    }
    if (tc.expect_gas_used_gt) |gas| {
        try expect(result.gas_used > gas);
    }
    if (tc.expect_gas_used_lt) |gas| {
        try expect(result.gas_used < gas);
    }

    // Verify context in output.
    if (tc.expected_caller_in_output) |addr| {
        try expect(result.output.len >= 20);
        const returned_addr = extractAddressFromReturn(result.output);
        try expect(std.mem.eql(u8, &returned_addr.inner.bytes, &addr.inner.bytes));
    }
    if (tc.expected_address_in_output) |addr| {
        try expect(result.output.len >= 20);
        const returned_addr = extractAddressFromReturn(result.output);
        try expect(std.mem.eql(u8, &returned_addr.inner.bytes, &addr.inner.bytes));
    }
    if (tc.expected_value_in_output) |val| {
        try expect(result.output.len >= 32);
        const returned_val = extractU64FromReturn(result.output);
        try expectEqual(val, returned_val);
    }

    // Verify depth.
    if (tc.expected_final_depth) |depth| {
        try expectEqual(depth, evm.depth);
    }

    // Verify return data buffer.
    if (tc.expected_return_buffer_len) |len| {
        try expectEqual(len, evm.return_data_buffer.len);
    }
    if (tc.expected_return_buffer_byte) |byte| {
        try expect(evm.return_data_buffer.len >= 32);
        try expectEqual(byte, evm.return_data_buffer[31]);
    }
}

/// Run multiple test cases.
pub fn runTestCases(test_cases: []const TestCase) !void {
    for (test_cases) |tc| {
        try runTestCase(tc);
    }
}
