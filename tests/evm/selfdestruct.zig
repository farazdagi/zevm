//! SELFDESTRUCT integration tests.

const std = @import("std");
const zevm = @import("zevm");
const th = @import("test_helpers.zig");

const Evm = th.Evm;
const CallExecutor = th.CallExecutor;
const CreateExecutor = zevm.CreateExecutor;
const ExecutionStatus = th.ExecutionStatus;
const Address = th.Address;
const U256 = th.U256;
const Env = th.Env;
const Spec = th.Spec;
const MockHost = th.MockHost;

const expect = th.expect;
const expectEqual = th.expectEqual;

// Test addresses
const CONTRACT = Address.init([_]u8{0} ** 19 ++ [_]u8{0x01});
const BENEFICIARY = Address.init([_]u8{0} ** 19 ++ [_]u8{0x02});
const CREATOR = Address.init([_]u8{0} ** 19 ++ [_]u8{0x03});

/// Create bytecode that selfdestructs to the given address.
/// PUSH20 <address>, SELFDESTRUCT
fn createSelfdestructContract(beneficiary: Address) [22]u8 {
    var code: [22]u8 = undefined;
    code[0] = 0x73; // PUSH20
    @memcpy(code[1..21], &beneficiary.inner.bytes);
    code[21] = 0xFF; // SELFDESTRUCT
    return code;
}

/// Init code that returns a selfdestruct contract.
fn createSelfdestructInitCode(beneficiary: Address) [34]u8 {
    var init_code: [34]u8 = undefined;

    // Runtime code: PUSH20 <beneficiary>, SELFDESTRUCT (22 bytes)
    const runtime = createSelfdestructContract(beneficiary);

    // PUSH22 <runtime_code>
    init_code[0] = 0x75; // PUSH22
    @memcpy(init_code[1..23], &runtime);

    // PUSH1 0, MSTORE
    init_code[23] = 0x60; // PUSH1
    init_code[24] = 0x00; // offset 0
    init_code[25] = 0x52; // MSTORE

    // PUSH1 22, PUSH1 10, RETURN (return from byte 10 = 32-22)
    init_code[26] = 0x60; // PUSH1
    init_code[27] = 0x16; // 22 bytes (runtime code size)
    init_code[28] = 0x60; // PUSH1
    init_code[29] = 0x0A; // offset 10 (32 - 22 = 10)
    init_code[30] = 0xF3; // RETURN

    // Padding
    init_code[31] = 0x00;
    init_code[32] = 0x00;
    init_code[33] = 0x00;

    return init_code;
}

test "SELFDESTRUCT: basic behavior" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    // Setup: CONTRACT has 1000 wei, BENEFICIARY has 500 wei.
    try mock.setBalance(CONTRACT, U256.fromU64(1000));
    try mock.setBalance(BENEFICIARY, U256.fromU64(500));

    // Code: SELFDESTRUCT, then INVALID (0xFE) to verify halt.
    var code: [23]u8 = undefined;
    const sd = createSelfdestructContract(BENEFICIARY);
    @memcpy(code[0..22], &sd);
    code[22] = 0xFE; // INVALID - should never be reached
    try mock.setCode(CONTRACT, &code);

    var evm = Evm.init(allocator, &env, mock.host(), Spec.CANCUN);
    defer evm.deinit();

    const inputs = CallExecutor.Inputs{
        .kind = .CALL,
        .target = CONTRACT,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = true,
    };

    const result = try evm.call(inputs);

    // Status is SELFDESTRUCT (not SUCCESS, not INVALID_OPCODE).
    try expectEqual(ExecutionStatus.SELFDESTRUCT, result.status);
    try expect(result.status != .SUCCESS);

    // Balance transferred correctly.
    try expectEqual(U256.ZERO, mock.host().balance(CONTRACT));
    try expectEqual(U256.fromU64(1500), mock.host().balance(BENEFICIARY));
}

test "SELFDESTRUCT: rejects in static context" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    const code = createSelfdestructContract(BENEFICIARY);
    try mock.setCode(CONTRACT, &code);

    var evm = Evm.init(allocator, &env, mock.host(), Spec.CANCUN);
    defer evm.deinit();

    // Use STATICCALL which sets is_static = true.
    const inputs = CallExecutor.Inputs{
        .kind = .STATICCALL,
        .target = CONTRACT,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = false,
    };

    const result = try evm.call(inputs);

    // Should revert due to state modification in static context.
    try expectEqual(ExecutionStatus.REVERT, result.status);
}

test "SELFDESTRUCT: gas refund by fork (EIP-3529)" {
    const TestCase = struct {
        spec: Spec,
        expected_refund: i64,
    };

    const test_cases = [_]TestCase{
        // Pre-London: 24000 refund.
        .{ .spec = Spec.ISTANBUL, .expected_refund = 24000 },
        // London+ (EIP-3529): No refund.
        .{ .spec = Spec.LONDON, .expected_refund = 0 },
    };

    for (test_cases) |tc| {
        const allocator = std.testing.allocator;
        var env = Env.default();
        var mock = MockHost.init(allocator);
        defer mock.deinit();

        try mock.setBalance(CONTRACT, U256.fromU64(1000));

        const code = createSelfdestructContract(BENEFICIARY);
        try mock.setCode(CONTRACT, &code);

        var evm = Evm.init(allocator, &env, mock.host(), tc.spec);
        defer evm.deinit();

        const inputs = CallExecutor.Inputs{
            .kind = .CALL,
            .target = CONTRACT,
            .caller = th.CALLER,
            .value = U256.ZERO,
            .input = &[_]u8{},
            .gas_limit = 100000,
            .transfer_value = true,
        };

        const result = try evm.call(inputs);

        try expectEqual(ExecutionStatus.SELFDESTRUCT, result.status);
        try expectEqual(tc.expected_refund, result.gas_refund);
    }
}

test "SELFDESTRUCT: destruction behavior by fork (EIP-6780)" {
    const TestCase = struct {
        spec: Spec,
        expected_destroyed: bool,
        expected_code_size: u64,
        expected_nonce: u64,
    };

    const test_cases = [_]TestCase{
        // Pre-Cancun: contract destroyed.
        .{ .spec = Spec.SHANGHAI, .expected_destroyed = true, .expected_code_size = 0, .expected_nonce = 0 },
        // Cancun+ (EIP-6780): not created this tx, so NOT destroyed.
        .{ .spec = Spec.CANCUN, .expected_destroyed = false, .expected_code_size = 22, .expected_nonce = 5 },
    };

    for (test_cases) |tc| {
        const allocator = std.testing.allocator;
        var env = Env.default();
        var mock = MockHost.init(allocator);
        defer mock.deinit();

        // Setup contract with balance, code, nonce (NOT created this tx).
        try mock.setBalance(CONTRACT, U256.fromU64(1000));
        const code = createSelfdestructContract(BENEFICIARY);
        try mock.setCode(CONTRACT, &code);
        try mock.setNonce(CONTRACT, 5);

        var evm = Evm.init(allocator, &env, mock.host(), tc.spec);
        defer evm.deinit();

        const inputs = CallExecutor.Inputs{
            .kind = .CALL,
            .target = CONTRACT,
            .caller = th.CALLER,
            .value = U256.ZERO,
            .input = &[_]u8{},
            .gas_limit = 100000,
            .transfer_value = true,
        };

        const result = try evm.call(inputs);

        try expectEqual(ExecutionStatus.SELFDESTRUCT, result.status);

        // Balance always transferred.
        try expectEqual(U256.ZERO, mock.host().balance(CONTRACT));
        try expectEqual(U256.fromU64(1000), mock.host().balance(BENEFICIARY));

        // Account existence and state depends on fork.
        try expectEqual(!tc.expected_destroyed, mock.host().accountExists(CONTRACT));
        try expectEqual(tc.expected_code_size, mock.host().codeSize(CONTRACT));
        try expectEqual(tc.expected_nonce, mock.host().nonce(CONTRACT));
    }
}

test "SELFDESTRUCT: Cancun+ destroys if created in same tx" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    // Give creator enough balance.
    try mock.setBalance(CREATOR, U256.fromU64(1000000));

    // Use Cancun (EIP-6780).
    var evm = Evm.init(allocator, &env, mock.host(), Spec.CANCUN);
    defer evm.deinit();

    // Create a contract that will selfdestruct to BENEFICIARY.
    const init_code = createSelfdestructInitCode(BENEFICIARY);
    const create_inputs = CreateExecutor.Inputs{
        .caller = CREATOR,
        .kind = .CREATE,
        .value = U256.fromU64(1000), // Send 1000 wei to new contract
        .init_code = &init_code,
        .gas_limit = 500000,
    };

    const create_result = try evm.create(create_inputs);
    try expectEqual(ExecutionStatus.SUCCESS, create_result.status);
    const created_address = create_result.address.?;

    // Now call the created contract (which will selfdestruct).
    const call_inputs = CallExecutor.Inputs{
        .kind = .CALL,
        .target = created_address,
        .caller = CREATOR,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .transfer_value = true,
    };

    const call_result = try evm.call(call_inputs);

    try expectEqual(ExecutionStatus.SELFDESTRUCT, call_result.status);

    // EIP-6780: Contract WAS created this tx, so it SHOULD be destroyed.
    try expect(!mock.host().accountExists(created_address));
    try expectEqual(@as(u64, 0), mock.host().codeSize(created_address));

    // Balance should have been transferred to beneficiary.
    try expectEqual(U256.fromU64(1000), mock.host().balance(BENEFICIARY));
}

test "SELFDESTRUCT: called contract selfdestructing returns success to caller" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();

    // Setup: CONTRACT will selfdestruct.
    try mock.setBalance(CONTRACT, U256.fromU64(1000));
    const sd_code = createSelfdestructContract(BENEFICIARY);
    try mock.setCode(CONTRACT, &sd_code);

    // Create caller contract that CALLs CONTRACT and returns success status.
    // Code: PUSH20 CONTRACT, GAS, CALL (simplified - just does the call).
    // We use a simple CALL with 0 value, 0 args, 0 ret.
    var caller_code: [44]u8 = undefined;
    // PUSH1 0 (retSize)
    caller_code[0] = 0x60;
    caller_code[1] = 0x00;
    // PUSH1 0 (retOffset)
    caller_code[2] = 0x60;
    caller_code[3] = 0x00;
    // PUSH1 0 (argsSize)
    caller_code[4] = 0x60;
    caller_code[5] = 0x00;
    // PUSH1 0 (argsOffset)
    caller_code[6] = 0x60;
    caller_code[7] = 0x00;
    // PUSH1 0 (value)
    caller_code[8] = 0x60;
    caller_code[9] = 0x00;
    // PUSH20 CONTRACT (target address)
    caller_code[10] = 0x73;
    @memcpy(caller_code[11..31], &CONTRACT.inner.bytes);
    // PUSH2 0xFFFF (gas)
    caller_code[31] = 0x61;
    caller_code[32] = 0xFF;
    caller_code[33] = 0xFF;
    // CALL
    caller_code[34] = 0xF1;
    // Now stack has success (1 or 0). Store it and return.
    // PUSH1 0, MSTORE
    caller_code[35] = 0x60;
    caller_code[36] = 0x00;
    caller_code[37] = 0x52;
    // PUSH1 32, PUSH1 0, RETURN
    caller_code[38] = 0x60;
    caller_code[39] = 0x20;
    caller_code[40] = 0x60;
    caller_code[41] = 0x00;
    caller_code[42] = 0xF3;
    caller_code[43] = 0x00; // padding

    const CALLER_CONTRACT = Address.init([_]u8{0} ** 19 ++ [_]u8{0x10});
    try mock.setCode(CALLER_CONTRACT, &caller_code);

    var evm = Evm.init(allocator, &env, mock.host(), Spec.CANCUN);
    defer evm.deinit();

    const inputs = CallExecutor.Inputs{
        .kind = .CALL,
        .target = CALLER_CONTRACT,
        .caller = th.CALLER,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 200000,
        .transfer_value = true,
    };

    const result = try evm.call(inputs);

    // Outer call should succeed.
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // Return data should contain 1 (success from inner CALL).
    try expect(result.output.len == 32);
    try expectEqual(@as(u8, 1), result.output[31]);
}
