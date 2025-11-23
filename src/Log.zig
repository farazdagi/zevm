//! EVM event log entry.
//!
//! This is a data transfer object - it does not own the data slice.
//! The host is responsible for copying data if it needs to persist logs.

const std = @import("std");
const Address = @import("primitives/address.zig").Address;
const B256 = @import("primitives/bytes.zig").B256;

const Log = @This();

/// Address of the contract that emitted this log.
address: Address,

/// Storage for indexed event parameters (topics).
/// Maximum 4 topics per EVM specification.
topics_storage: [4]B256,

/// Number of valid topics (0-4).
/// Using u3 makes the 0-4 constraint explicit in the type system.
topic_count: u3,

/// Non-indexed event data.
/// Not owned by this struct - borrowed from memory or owned by host.
data: []const u8,

/// Create a new log entry.
///
/// The `data` slice is not copied - the caller retains ownership.
/// Since topic_count is u3, it can only represent 0-4, so no error needed.
pub fn init(address: Address, topic_list: []const B256, data: []const u8) Log {
    var log = Log{
        .address = address,
        .topics_storage = undefined,
        .topic_count = @intCast(topic_list.len),
        .data = data,
    };

    if (topic_list.len > 0) {
        @memcpy(log.topics_storage[0..topic_list.len], topic_list);
    }

    return log;
}

/// Get the log topics as a const slice.
pub fn topics(self: Log) []const B256 {
    return self.topics_storage[0..self.topic_count];
}

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Log: initialization with various topic counts" {
    const test_cases = [_]struct {
        topic_count: u3,
    }{
        // Zero topics
        .{ .topic_count = 0 },
        // One topic
        .{ .topic_count = 1 },
        // Four topics (maximum)
        .{ .topic_count = 4 },
    };

    for (test_cases) |tc| {
        const topics_arr = [_]B256{B256.zero()} ** 4;
        const log = Log.init(Address.zero(), topics_arr[0..tc.topic_count], &[_]u8{});

        try expectEqual(tc.topic_count, log.topic_count);
        try expectEqual(tc.topic_count, log.topics().len);
        try expectEqual(0, log.data.len);

        if (tc.topic_count > 0) {
            try expect(log.topics()[0].eql(B256.zero()));
        }
    }
}

test "Log: all fields stored correctly" {
    const U256 = @import("primitives/big.zig").U256;

    // Create two distinct topics with specific byte patterns
    var bytes1: [32]u8 = [_]u8{0} ** 32;
    bytes1[0] = 1;
    var bytes2: [32]u8 = [_]u8{0} ** 32;
    bytes2[0] = 2;
    const topic1 = B256.init(bytes1);
    const topic2 = B256.init(bytes2);

    // Create specific data
    const data = [_]u8{ 1, 2, 3, 4 };

    // Create specific address
    const addr = Address.fromU256(U256.fromU64(0x1234));

    // Initialize log with all fields
    const log = Log.init(addr, &[_]B256{ topic1, topic2 }, &data);

    // Verify topics are stored correctly
    const topics_slice = log.topics();
    try expectEqual(2, topics_slice.len);
    try expect(topics_slice[0].bytes[0] == 1);
    try expect(topics_slice[0].bytes[31] == 0);
    try expect(topics_slice[1].bytes[0] == 2);
    try expect(topics_slice[1].bytes[31] == 0);

    // Verify data is borrowed correctly
    try expectEqual(4, log.data.len);
    try expectEqual(1, log.data[0]);
    try expectEqual(4, log.data[3]);

    // Verify address is stored correctly
    try expect(log.address.eql(addr));
}
