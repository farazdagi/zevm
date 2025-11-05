const std = @import("std");
const zevm = @import("zevm");

const Hardfork = zevm.hardfork.Hardfork;
const Spec = zevm.hardfork.Spec;
const Gas = zevm.interpreter.Gas;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// ============================================================================
// Fork Refund Behavior Tests (EIP-3529)
// ============================================================================

test "Hardfork: pre-EIP-3529 refund cap (used/2)" {
    // Berlin and earlier: refund cap is used/2
    const spec = Spec.forFork(.BERLIN);
    var gas = Gas.init(10000, spec);
    try gas.consume(5000);

    // Try to refund 3000, cap is used/2 = 2500
    gas.refund(3000);
    try expectEqual(@as(u64, 3000), gas.refunded); // Tracks full amount
    try expectEqual(@as(u64, 2500), gas.finalRefund()); // But capped at 2500
}

test "Hardfork: post-EIP-3529 refund cap (used/5)" {
    // London and later: refund cap is used/5
    const spec = Spec.forFork(.LONDON);
    var gas = Gas.init(10000, spec);
    try gas.consume(5000);

    // Try to refund 3000, cap is used/5 = 1000
    gas.refund(3000);
    try expectEqual(@as(u64, 3000), gas.refunded); // Tracks full amount
    try expectEqual(@as(u64, 1000), gas.finalRefund()); // But capped at 1000
}

test "Hardfork: refund evolution across forks" {
    const test_cases = [_]struct {
        fork: Hardfork,
        divisor: u64,
        expected_cap: u64, // For 5000 gas used
    }{
        .{ .fork = .FRONTIER, .divisor = 2, .expected_cap = 2500 },
        .{ .fork = .HOMESTEAD, .divisor = 2, .expected_cap = 2500 },
        .{ .fork = .BERLIN, .divisor = 2, .expected_cap = 2500 },
        .{ .fork = .LONDON, .divisor = 5, .expected_cap = 1000 },
        .{ .fork = .MERGE, .divisor = 5, .expected_cap = 1000 },
        .{ .fork = .SHANGHAI, .divisor = 5, .expected_cap = 1000 },
        .{ .fork = .CANCUN, .divisor = 5, .expected_cap = 1000 },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        try expectEqual(tc.divisor, spec.max_refund_quotient);

        var gas = Gas.init(10000, spec);
        try gas.consume(5000);
        gas.refund(3000);
        try expectEqual(tc.expected_cap, gas.finalRefund());
    }
}

// ============================================================================
// Storage Access Costs (EIP-2929)
// ============================================================================

test "Hardfork: SLOAD costs pre-EIP-2929" {
    // Before Berlin, no cold/warm distinction
    const spec = Spec.forFork(.HOMESTEAD);
    const gas = Gas.init(100000, spec);

    // Pre-EIP-2929: cold_sload_cost is same as old cost (200 for Homestead)
    try expectEqual(@as(u64, 200), gas.spec.cold_sload_cost);
}

test "Hardfork: SLOAD costs post-EIP-2929" {
    // Berlin introduces cold/warm access
    const spec = Spec.forFork(.BERLIN);
    const gas = Gas.init(100000, spec);

    try expectEqual(@as(u64, 2100), gas.spec.cold_sload_cost);
    try expectEqual(@as(u64, 100), gas.spec.warm_storage_read_cost);
}

test "Hardfork: cold account access costs" {
    const pre_berlin = Spec.forFork(.HOMESTEAD);
    const post_berlin = Spec.forFork(.BERLIN);

    const gas_pre = Gas.init(100000, pre_berlin);
    const gas_post = Gas.init(100000, post_berlin);

    // Pre-Berlin: lower cost
    try expectEqual(@as(u64, 700), gas_pre.spec.cold_account_access_cost);

    // Post-Berlin (EIP-2929): higher cold access cost
    try expectEqual(@as(u64, 2600), gas_post.spec.cold_account_access_cost);
}

// ============================================================================
// Storage Refund Amounts
// ============================================================================

test "Hardfork: SSTORE clear refund across forks" {
    const test_cases = [_]struct {
        fork: Hardfork,
        expected: u64,
    }{
        .{ .fork = .FRONTIER, .expected = 15000 },
        .{ .fork = .HOMESTEAD, .expected = 15000 },
        .{ .fork = .BERLIN, .expected = 15000 },
        .{ .fork = .LONDON, .expected = 4800 }, // EIP-3529 reduced refund
        .{ .fork = .CANCUN, .expected = 4800 },
    };

    for (test_cases) |tc| {
        const spec = Spec.forFork(tc.fork);
        const gas = Gas.init(100000, spec);
        try expectEqual(tc.expected, gas.spec.sstore_clears_schedule);
    }
}

test "Hardfork: SELFDESTRUCT refund removal" {
    // Pre-EIP-3529: 24000 gas refund
    const berlin = Spec.forFork(.BERLIN);
    const gas_berlin = Gas.init(100000, berlin);
    try expectEqual(@as(u64, 24000), gas_berlin.spec.selfdestruct_refund);

    // Post-EIP-3529: no refund
    const london = Spec.forFork(.LONDON);
    const gas_london = Gas.init(100000, london);
    try expectEqual(@as(u64, 0), gas_london.spec.selfdestruct_refund);
}

// ============================================================================
// EIP Availability Tests
// ============================================================================

test "Hardfork: PUSH0 availability (EIP-3855)" {
    // PUSH0 introduced in Shanghai
    try expect(!Spec.forFork(.BERLIN).has_push0);
    try expect(!Spec.forFork(.LONDON).has_push0);
    try expect(!Spec.forFork(.MERGE).has_push0);
    try expect(Spec.forFork(.SHANGHAI).has_push0);
    try expect(Spec.forFork(.CANCUN).has_push0);
}

test "Hardfork: BASEFEE availability (EIP-3198)" {
    // BASEFEE introduced in London
    try expect(!Spec.forFork(.BERLIN).has_basefee);
    try expect(Spec.forFork(.LONDON).has_basefee);
    try expect(Spec.forFork(.MERGE).has_basefee);
    try expect(Spec.forFork(.SHANGHAI).has_basefee);
}

test "Hardfork: PREVRANDAO availability (EIP-4399)" {
    // PREVRANDAO introduced in Merge
    try expect(!Spec.forFork(.LONDON).has_prevrandao);
    try expect(Spec.forFork(.MERGE).has_prevrandao);
    try expect(Spec.forFork(.SHANGHAI).has_prevrandao);
}

test "Hardfork: transient storage availability (EIP-1153)" {
    // TLOAD/TSTORE introduced in Cancun
    try expect(!Spec.forFork(.SHANGHAI).has_tstore);
    try expect(Spec.forFork(.CANCUN).has_tstore);
}

test "Hardfork: blob operations availability (EIP-4844)" {
    // Blob opcodes introduced in Cancun
    try expect(!Spec.forFork(.SHANGHAI).has_blob_opcodes);
    try expect(Spec.forFork(.CANCUN).has_blob_opcodes);
}

test "Hardfork: MCOPY availability (EIP-5656)" {
    // MCOPY introduced in Cancun
    try expect(!Spec.forFork(.SHANGHAI).has_mcopy);
    try expect(Spec.forFork(.CANCUN).has_mcopy);
}

// ============================================================================
// Code Size Limits
// ============================================================================

test "Hardfork: max code size (EIP-170)" {
    // EIP-170 introduced 24576 byte limit in Spurious Dragon
    const frontier = Spec.forFork(.FRONTIER);
    const homestead = Spec.forFork(.HOMESTEAD);
    const cancun = Spec.forFork(.CANCUN);

    // All forks have the limit (introduced early)
    try expectEqual(@as(usize, 24576), frontier.max_code_size);
    try expectEqual(@as(usize, 24576), homestead.max_code_size);
    try expectEqual(@as(usize, 24576), cancun.max_code_size);
}

test "Hardfork: max initcode size (EIP-3860)" {
    // EIP-3860 introduced 49152 byte limit for initcode in Shanghai
    const london = Spec.forFork(.LONDON);
    const shanghai = Spec.forFork(.SHANGHAI);

    try expect(london.max_initcode_size == null);
    try expectEqual(@as(usize, 49152), shanghai.max_initcode_size.?);
}

// ============================================================================
// Integration Tests: Gas with Different Forks
// ============================================================================

test "Hardfork: integration - same code, different fork costs" {
    // Simulate SSTORE clear operation across forks

    // Berlin: higher refund
    {
        const spec = Spec.forFork(.BERLIN);
        var gas = Gas.init(100000, spec);
        try gas.consume(5000);
        const refund_amount = gas.spec.sstore_clears_schedule;
        gas.refund(refund_amount);

        // Berlin: 15000 refund, capped at used/2 = 2500
        try expectEqual(@as(u64, 15000), gas.refunded);
        try expectEqual(@as(u64, 2500), gas.finalRefund());
    }

    // London: lower refund
    {
        const spec = Spec.forFork(.LONDON);
        var gas = Gas.init(100000, spec);
        try gas.consume(5000);
        const refund_amount = gas.spec.sstore_clears_schedule;
        gas.refund(refund_amount);

        // London: 4800 refund, capped at used/5 = 1000
        try expectEqual(@as(u64, 4800), gas.refunded);
        try expectEqual(@as(u64, 1000), gas.finalRefund());
    }
}

test "Hardfork: integration - fork comparison for storage" {
    // Compare total gas cost for storage operations across forks

    const forks = [_]Hardfork{ .HOMESTEAD, .BERLIN, .LONDON, .SHANGHAI };
    var results: [4]u64 = undefined;

    for (forks, 0..) |fork, i| {
        const spec = Spec.forFork(fork);
        var gas = Gas.init(100000, spec);

        // Simulate: cold SLOAD + SSTORE clear
        try gas.consume(gas.spec.cold_sload_cost);
        try gas.consume(5000); // Approximate SSTORE cost
        gas.refund(gas.spec.sstore_clears_schedule);

        results[i] = gas.used - gas.finalRefund();
    }

    // Berlin should have highest net cost (high cold SLOAD)
    // London should have even higher net (lower refund)
    try expect(results[1] < results[2]); // Berlin < London
}

// ============================================================================
// Fork Comparison and Ordering
// ============================================================================

test "Hardfork: fork ordering and comparison" {
    try expect(Hardfork.FRONTIER.isAtLeast(.FRONTIER));
    try expect(Hardfork.LONDON.isAtLeast(.BERLIN));
    try expect(Hardfork.CANCUN.isAtLeast(.SHANGHAI));
    try expect(!Hardfork.BERLIN.isAtLeast(.LONDON));

    try expect(Hardfork.BERLIN.isBefore(.LONDON));
    try expect(Hardfork.SHANGHAI.isBefore(.CANCUN));
    try expect(!Hardfork.LONDON.isBefore(.BERLIN));
}

test "Hardfork: fork names" {
    try expectEqualStrings("Frontier", Hardfork.FRONTIER.name());
    try expectEqualStrings("London", Hardfork.LONDON.name());
    try expectEqualStrings("Cancun", Hardfork.CANCUN.name());
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Hardfork: zero gas used with refunds" {
    const spec = Spec.forFork(.LONDON);
    var gas = Gas.init(10000, spec);

    // No gas used, try to refund
    gas.refund(1000);
    try expectEqual(@as(u64, 1000), gas.refunded);
    try expectEqual(@as(u64, 0), gas.finalRefund()); // Cap is 0/5 = 0
}

test "Hardfork: refund within cap" {
    const spec = Spec.forFork(.LONDON);
    var gas = Gas.init(10000, spec);
    try gas.consume(5000);

    // Refund amount within cap
    gas.refund(500); // Cap is 5000/5 = 1000
    try expectEqual(@as(u64, 500), gas.finalRefund()); // Not capped
}

// ============================================================================
// Prague Fork Tests (May 2025)
// ============================================================================

test "Hardfork: Prague - blob capacity doubled (EIP-7691)" {
    const cancun = Spec.forFork(.CANCUN);
    const prague = Spec.forFork(.PRAGUE);

    // Cancun: target 3, max 6
    try expectEqual(@as(u8, 3), cancun.target_blobs_per_block);
    try expectEqual(@as(u8, 6), cancun.max_blobs_per_block);

    // Prague: target 6, max 9 (doubled)
    try expectEqual(@as(u8, 6), prague.target_blobs_per_block);
    try expectEqual(@as(u8, 9), prague.max_blobs_per_block);
}

test "Hardfork: Prague - EIP-7702 availability" {
    // EIP-7702: EOA account abstraction
    try expect(!Spec.forFork(.CANCUN).has_eip7702);
    try expect(Spec.forFork(.PRAGUE).has_eip7702);
}

test "Hardfork: Prague - EIP-2537 BLS precompiles" {
    // BLS12-381 curve operations
    try expect(!Spec.forFork(.CANCUN).has_bls_precompiles);
    try expect(Spec.forFork(.PRAGUE).has_bls_precompiles);
}

test "Hardfork: Prague - EIP-2935 historical block hashes" {
    // Extended from 256 to 8192 blocks
    try expect(!Spec.forFork(.CANCUN).has_historical_block_hashes);
    try expect(Spec.forFork(.PRAGUE).has_historical_block_hashes);
}

test "Hardfork: Prague inherits all Cancun features" {
    const prague = Spec.forFork(.PRAGUE);

    // Should have all Cancun features
    try expect(prague.has_push0);
    try expect(prague.has_basefee);
    try expect(prague.has_prevrandao);
    try expect(prague.has_blob_opcodes);
    try expect(prague.has_tstore);
    try expect(prague.has_mcopy);

    // Plus new Prague features
    try expect(prague.has_eip7702);
    try expect(prague.has_bls_precompiles);
    try expect(prague.has_historical_block_hashes);
}

test "Hardfork: Prague is latest fork" {
    try expectEqual(Hardfork.PRAGUE, Hardfork.LATEST);
}

test "Hardfork: Prague fork ordering" {
    try expect(Hardfork.PRAGUE.isAtLeast(.CANCUN));
    try expect(Hardfork.PRAGUE.isAtLeast(.SHANGHAI));
    try expect(Hardfork.PRAGUE.isAtLeast(.LONDON));
    try expect(!Hardfork.CANCUN.isAtLeast(.PRAGUE));
}

test "Hardfork: Prague fork name" {
    try expectEqualStrings("Prague", Hardfork.PRAGUE.name());
}
