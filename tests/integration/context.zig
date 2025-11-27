const std = @import("std");
const zevm = @import("zevm");
const Env = zevm.context.Env;
const BlockEnv = zevm.context.BlockEnv;
const TxEnv = zevm.context.TxEnv;
const U256 = zevm.primitives.U256;
const Address = zevm.primitives.Address;
const B256 = zevm.primitives.B256;

const expectEqual = std.testing.expectEqual;

test "BlockEnv: default initialization" {
    const block = BlockEnv.default();

    try expectEqual(1, block.number);
    try expectEqual(30_000_000, block.gas_limit);
    try expectEqual(Address.zero(), block.coinbase);
}

test "TxEnv: default initialization" {
    const tx = TxEnv.default();

    try expectEqual(Address.zero(), tx.caller);
    try expectEqual(Address.zero(), tx.origin);
    try expectEqual(U256.ZERO, tx.value);
    try expectEqual(0, tx.data.len);
}

test "Env: wraps both contexts" {
    const env = Env.default();

    try expectEqual(1, env.block.number);
    try expectEqual(Address.zero(), env.tx.caller);
}

test "BlockEnv: custom initialization" {
    const block = BlockEnv{
        .number = 100,
        .coinbase = Address.fromHex("0x000000000000000000000000000000000000ABCD") catch unreachable,
        .timestamp = 1234567890,
        .gas_limit = 15_000_000,
        .basefee = U256.fromU64(10),
        .prevrandao = B256.fromHex("0x0000000000000000000000000000000000000000000000000000000000000042") catch unreachable,
    };

    try expectEqual(100, block.number);
    try expectEqual(1234567890, block.timestamp);
    try expectEqual(U256.fromU64(10), block.basefee);
}

test "TxEnv: custom initialization" {
    const caller_addr = Address.fromHex("0x0000000000000000000000000000000000001111") catch unreachable;
    const origin_addr = Address.fromHex("0x0000000000000000000000000000000000002222") catch unreachable;

    const tx = TxEnv{
        .caller = caller_addr,
        .origin = origin_addr,
        .to = null,
        .gas_price = U256.fromU64(50),
        .value = U256.fromU64(1000),
        .data = &[_]u8{ 0xAA, 0xBB },
    };

    try expectEqual(caller_addr, tx.caller);
    try expectEqual(origin_addr, tx.origin);
    try expectEqual(U256.fromU64(50), tx.gas_price);
    try expectEqual(2, tx.data.len);
}

test "Env: custom configuration" {
    var block = BlockEnv.default();
    block.number = 12345;
    block.timestamp = 1234567890;

    var tx = TxEnv.default();
    tx.caller = Address.fromHex("0x000000000000000000000000000000000000ABCD") catch unreachable;
    tx.value = U256.fromU64(999);

    const env = Env{ .block = block, .tx = tx };

    try expectEqual(12345, env.block.number);
    try expectEqual(1234567890, env.block.timestamp);
    try expectEqual(Address.fromHex("0x000000000000000000000000000000000000ABCD") catch unreachable, env.tx.caller);
    try expectEqual(U256.fromU64(999), env.tx.value);
}
