const std = @import("std");
const zevm = @import("zevm");
const FixedGasCosts = zevm.interpreter.gas.FixedGasCosts;
const Hardfork = zevm.hardfork.Hardfork;
const Opcode = zevm.interpreter.Opcode;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "EIP-150: gas cost increases for IO-heavy operations" {
    // EIP-150 (Tangerine) increased gas costs of opcodes
    // that could be used in DoS attacks. This test verifies the costs
    // changed correctly at the Tangerine fork boundary.
    const test_cases = [_]struct {
        fork: Hardfork,
        // Expected costs for each opcode affected by EIP-150
        extcodesize: u64,
        extcodecopy: u64,
        balance: u64,
        sload: u64,
        call: u64,
        delegatecall: u64,
        callcode: u64,
        selfdestruct: u64,
    }{
        // Pre-EIP-150 forks (old costs)
        .{
            .fork = .FRONTIER,
            .extcodesize = 20,
            .extcodecopy = 20,
            .balance = 20,
            .sload = 50,
            .call = 40,
            .delegatecall = 0, // Not defined in Frontier
            .callcode = 40,
            .selfdestruct = 0,
        },
        .{
            .fork = .HOMESTEAD,
            .extcodesize = 20,
            .extcodecopy = 20,
            .balance = 20,
            .sload = 50,
            .call = 40,
            .delegatecall = 40, // Added in Homestead (EIP-7)
            .callcode = 40,
            .selfdestruct = 0,
        },
        // EIP-150 active (new costs)
        .{
            .fork = .TANGERINE,
            .extcodesize = 700,
            .extcodecopy = 700,
            .balance = 400,
            .sload = 200,
            .call = 700,
            .delegatecall = 700,
            .callcode = 700,
            .selfdestruct = 5000,
        },
        // Post-EIP-150 forks (costs should remain)
        .{
            .fork = .SPURIOUS_DRAGON,
            .extcodesize = 700,
            .extcodecopy = 700,
            .balance = 400,
            .sload = 200,
            .call = 700,
            .delegatecall = 700,
            .callcode = 700,
            .selfdestruct = 5000,
        },
        .{
            .fork = .BYZANTIUM,
            .extcodesize = 700,
            .extcodecopy = 700,
            .balance = 400,
            .sload = 200,
            .call = 700,
            .delegatecall = 700,
            .callcode = 700,
            .selfdestruct = 5000,
        },
    };

    for (test_cases) |tc| {
        const table = FixedGasCosts.forFork(tc.fork);

        // Verify EIP-150 affected opcodes
        try expectEqual(tc.extcodesize, table.costs[@intFromEnum(Opcode.EXTCODESIZE)]);
        try expectEqual(tc.extcodecopy, table.costs[@intFromEnum(Opcode.EXTCODECOPY)]);
        try expectEqual(tc.balance, table.costs[@intFromEnum(Opcode.BALANCE)]);
        try expectEqual(tc.sload, table.costs[@intFromEnum(Opcode.SLOAD)]);
        try expectEqual(tc.call, table.costs[@intFromEnum(Opcode.CALL)]);
        try expectEqual(tc.delegatecall, table.costs[@intFromEnum(Opcode.DELEGATECALL)]);
        try expectEqual(tc.callcode, table.costs[@intFromEnum(Opcode.CALLCODE)]);
        try expectEqual(tc.selfdestruct, table.costs[@intFromEnum(Opcode.SELFDESTRUCT)]);
    }
}

test "EIP-2929: gas cost increases for state access opcodes" {
    // EIP-2929 (Berlin fork) introduced warm/cold access costs for state access.
    // FixedGasCosts stores the "warm" (cached) access costs.
    // This test tracks the evolution of these costs from Tangerine through Prague.
    const test_cases = [_]struct {
        fork: Hardfork,
        // Expected warm costs for state access opcodes
        sload: u64,
        balance: u64,
        extcodesize: u64,
        extcodecopy: u64,
        extcodehash: u64,
        call: u64,
        callcode: u64,
        delegatecall: u64,
        staticcall: u64,
    }{
        // Tangerine: Post-EIP-150 costs
        .{
            .fork = .TANGERINE,
            .sload = 200,
            .balance = 400,
            .extcodesize = 700,
            .extcodecopy = 700,
            .extcodehash = 0, // Not defined yet
            .call = 700,
            .callcode = 700,
            .delegatecall = 700,
            .staticcall = 0, // Not defined yet
        },
        // Istanbul: EIP-1884 cost adjustments
        .{
            .fork = .ISTANBUL,
            .sload = 800, // Increased from 200
            .balance = 700, // Increased from 400
            .extcodesize = 700,
            .extcodecopy = 700,
            .extcodehash = 700, // EIP-1052: Added in Constantinople, cost increased here
            .call = 700,
            .callcode = 700,
            .delegatecall = 700,
            .staticcall = 700, // Inherited from Byzantium via Petersburg
        },
        // Berlin: EIP-2929 warm/cold access (warm costs = 100)
        .{
            .fork = .BERLIN,
            .sload = 100, // Cold: 2100
            .balance = 100, // Cold: 2600
            .extcodesize = 100, // Cold: 2600
            .extcodecopy = 100, // Cold: 2600
            .extcodehash = 100, // Cold: 2600
            .call = 100, // Cold: 2600
            .callcode = 100, // Cold: 2600
            .delegatecall = 100, // Cold: 2600
            .staticcall = 100, // Cold: 2600
        },
        // Post-Berlin: Maintain warm cost of 100
        .{
            .fork = .LONDON,
            .sload = 100,
            .balance = 100,
            .extcodesize = 100,
            .extcodecopy = 100,
            .extcodehash = 100,
            .call = 100,
            .callcode = 100,
            .delegatecall = 100,
            .staticcall = 100,
        },
        .{
            .fork = .SHANGHAI,
            .sload = 100,
            .balance = 100,
            .extcodesize = 100,
            .extcodecopy = 100,
            .extcodehash = 100,
            .call = 100,
            .callcode = 100,
            .delegatecall = 100,
            .staticcall = 100,
        },
        .{
            .fork = .CANCUN,
            .sload = 100,
            .balance = 100,
            .extcodesize = 100,
            .extcodecopy = 100,
            .extcodehash = 100,
            .call = 100,
            .callcode = 100,
            .delegatecall = 100,
            .staticcall = 100,
        },
        .{
            .fork = .PRAGUE,
            .sload = 100,
            .balance = 100,
            .extcodesize = 100,
            .extcodecopy = 100,
            .extcodehash = 100,
            .call = 100,
            .callcode = 100,
            .delegatecall = 100,
            .staticcall = 100,
        },
    };

    for (test_cases) |tc| {
        const table = FixedGasCosts.forFork(tc.fork);

        // Verify EIP-2929 affected opcodes
        try expectEqual(tc.sload, table.costs[@intFromEnum(Opcode.SLOAD)]);
        try expectEqual(tc.balance, table.costs[@intFromEnum(Opcode.BALANCE)]);
        try expectEqual(tc.extcodesize, table.costs[@intFromEnum(Opcode.EXTCODESIZE)]);
        try expectEqual(tc.extcodecopy, table.costs[@intFromEnum(Opcode.EXTCODECOPY)]);
        try expectEqual(tc.extcodehash, table.costs[@intFromEnum(Opcode.EXTCODEHASH)]);
        try expectEqual(tc.call, table.costs[@intFromEnum(Opcode.CALL)]);
        try expectEqual(tc.callcode, table.costs[@intFromEnum(Opcode.CALLCODE)]);
        try expectEqual(tc.delegatecall, table.costs[@intFromEnum(Opcode.DELEGATECALL)]);
        try expectEqual(tc.staticcall, table.costs[@intFromEnum(Opcode.STATICCALL)]);
    }
}

test "Berlin warm storage costs" {
    const berlin = FixedGasCosts.BERLIN;

    // Berlin introduced EIP-2929: warm/cold storage costs
    // Warm costs should be 100 (from Spec.BERLIN.warm_storage_read_cost)
    const test_cases = [_]struct {
        opcode: Opcode,
        expected: u64,
    }{
        .{ .opcode = .BALANCE, .expected = 100 },
        .{ .opcode = .SLOAD, .expected = 100 },
        .{ .opcode = .EXTCODESIZE, .expected = 100 },
        .{ .opcode = .EXTCODECOPY, .expected = 100 },
        .{ .opcode = .EXTCODEHASH, .expected = 100 },
        .{ .opcode = .CALL, .expected = 100 },
        .{ .opcode = .CALLCODE, .expected = 100 },
        .{ .opcode = .DELEGATECALL, .expected = 100 },
        .{ .opcode = .STATICCALL, .expected = 100 },
    };

    for (test_cases) |tc| {
        try expectEqual(tc.expected, berlin.costs[@intFromEnum(tc.opcode)]);
    }
}

test "Berlin vs Frontier cost changes" {
    const frontier = FixedGasCosts.FRONTIER;
    const berlin = FixedGasCosts.BERLIN;

    // BALANCE: 20 (Frontier) -> 100 (Berlin warm)
    try expectEqual(20, frontier.costs[@intFromEnum(Opcode.BALANCE)]);
    try expectEqual(100, berlin.costs[@intFromEnum(Opcode.BALANCE)]);

    // SLOAD: 50 (Frontier) -> 100 (Berlin warm)
    try expectEqual(50, frontier.costs[@intFromEnum(Opcode.SLOAD)]);
    try expectEqual(100, berlin.costs[@intFromEnum(Opcode.SLOAD)]);

    // CALL: 40 (Frontier) -> 100 (Berlin warm)
    try expectEqual(40, frontier.costs[@intFromEnum(Opcode.CALL)]);
    try expectEqual(100, berlin.costs[@intFromEnum(Opcode.CALL)]);

    // Opcodes that didn't change
    try expectEqual(frontier.costs[@intFromEnum(Opcode.ADD)], berlin.costs[@intFromEnum(Opcode.ADD)]);
    try expectEqual(frontier.costs[@intFromEnum(Opcode.MUL)], berlin.costs[@intFromEnum(Opcode.MUL)]);
}

test "London same as Berlin for gas costs" {
    const berlin = FixedGasCosts.BERLIN;
    const london = FixedGasCosts.LONDON;

    // London didn't change gas costs, only refund parameters
    // All opcode costs should be identical
    const test_opcodes = [_]Opcode{
        .ADD,
        .MUL,
        .BALANCE,
        .SLOAD,
        .CALL,
        .JUMP,
        .JUMPI,
        .CREATE,
    };

    for (test_opcodes) |opcode| {
        try expectEqual(berlin.costs[@intFromEnum(opcode)], london.costs[@intFromEnum(opcode)]);
    }
}

test "Fork evolution Frontier -> Berlin -> London" {
    const frontier = FixedGasCosts.FRONTIER;
    const berlin = FixedGasCosts.BERLIN;
    const london = FixedGasCosts.LONDON;

    // SLOAD evolution: 50 -> 100 -> 100
    try expectEqual(50, frontier.costs[@intFromEnum(Opcode.SLOAD)]);
    try expectEqual(100, berlin.costs[@intFromEnum(Opcode.SLOAD)]);
    try expectEqual(100, london.costs[@intFromEnum(Opcode.SLOAD)]);

    // BALANCE evolution: 20 -> 100 -> 100
    try expectEqual(20, frontier.costs[@intFromEnum(Opcode.BALANCE)]);
    try expectEqual(100, berlin.costs[@intFromEnum(Opcode.BALANCE)]);
    try expectEqual(100, london.costs[@intFromEnum(Opcode.BALANCE)]);

    // Unchanged opcodes remain consistent
    try expectEqual(3, frontier.costs[@intFromEnum(Opcode.ADD)]);
    try expectEqual(3, berlin.costs[@intFromEnum(Opcode.ADD)]);
    try expectEqual(3, london.costs[@intFromEnum(Opcode.ADD)]);
}

test "Undefined opcodes cost 0, defined opcodes have proper cost" {
    const london = FixedGasCosts.LONDON;
    const shanghai = FixedGasCosts.SHANGHAI;
    const cancun = FixedGasCosts.CANCUN;

    // PUSH0 undefined in London (pre-Shanghai)
    try expectEqual(0, london.costs[@intFromEnum(Opcode.PUSH0)]);

    // PUSH0 defined in Shanghai (EIP-3855)
    try expectEqual(2, shanghai.costs[@intFromEnum(Opcode.PUSH0)]); // base cost

    // TLOAD/TSTORE undefined in Shanghai
    try expectEqual(0, shanghai.costs[@intFromEnum(Opcode.TLOAD)]);
    try expectEqual(0, shanghai.costs[@intFromEnum(Opcode.TSTORE)]);

    // TLOAD/TSTORE defined in Cancun (EIP-1153)
    try expectEqual(100, cancun.costs[@intFromEnum(Opcode.TLOAD)]);
    try expectEqual(100, cancun.costs[@intFromEnum(Opcode.TSTORE)]);

    // MCOPY undefined in Shanghai
    try expectEqual(0, shanghai.costs[@intFromEnum(Opcode.MCOPY)]);

    // MCOPY defined in Cancun (EIP-5656)
    try expectEqual(3, cancun.costs[@intFromEnum(Opcode.MCOPY)]); // verylow cost
}
