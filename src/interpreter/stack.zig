const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const constants = @import("../primitives/constants.zig");
const U256 = @import("../primitives/big.zig").U256;

/// EVM stack implementation.
///
/// The EVM uses a stack-based architecture with a maximum depth of 1024 items.
/// Each item on the stack is a 256-bit word (U256).
pub const Stack = struct {
    /// Heap-allocated array (preallocated to STACK_LIMIT).
    data: []U256,

    /// Current number of items on the stack.
    len: usize,

    // Allocator for cleanup
    allocator: Allocator,

    const Self = @This();

    /// Maximum stack capacity as defined by the Ethereum specification.
    pub const CAPACITY: usize = constants.STACK_LIMIT;

    /// Errors that can occur during stack operations.
    pub const Error = error{
        StackOverflow,
        StackUnderflow,
    };

    /// Initialize a new stack with the given allocator.
    ///
    /// Pre-allocates capacity for `STACK_LIMIT` items to avoid reallocation.
    pub fn init(allocator: Allocator) !Self {
        const data = try allocator.alloc(U256, CAPACITY);
        return Self{
            .data = data,
            .len = 0,
            .allocator = allocator,
        };
    }

    /// Free the stack's memory.
    ///
    /// Must be called when done with the stack.
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    /// Push a value onto the stack.
    ///
    /// Returns `error.StackOverflow` if stack is full.
    pub fn push(self: *Self, value: U256) Error!void {
        if (self.len >= CAPACITY)
            return error.StackOverflow;

        self.data[self.len] = value;
        self.len += 1;
    }

    /// Pop a value from the stack.
    ///
    /// Returns `error.StackUnderflow` if stack is empty.
    pub fn pop(self: *Self) Error!U256 {
        if (self.len == 0)
            return error.StackUnderflow;

        self.len -= 1;
        return self.data[self.len];
    }

    /// Peek at the value at the given index from the top.
    ///
    /// Index 0 is the top of the stack, index 1 is second from top, etc.
    /// Returns `error.StackUnderflow` if index is out of bounds.
    pub fn peek(self: *const Self, index: usize) Error!U256 {
        if (index >= self.len)
            return error.StackUnderflow;
        return self.data[self.len - 1 - index];
    }

    /// Duplicate the value at the given index from the top (1-16).
    ///
    /// Returns `error.StackUnderflow` if index is invalid or out of bounds.
    pub fn dup(self: *Self, index: usize) Error!void {
        if (index == 0 or index > 16) {
            return error.StackUnderflow;
        }
        const value = try self.peek(index - 1);
        try self.push(value);
    }

    /// Swap the top value with the value at the given index (1-16).
    ///
    /// Returns `error.StackUnderflow` if index is invalid or out of bounds.
    pub fn swap(self: *Self, index: usize) Error!void {
        if (index == 0 or index > 16 or index >= self.len)
            return error.StackUnderflow;

        const top_idx = self.len - 1;
        const swap_idx = self.len - 1 - index;
        std.mem.swap(U256, &self.data[top_idx], &self.data[swap_idx]);
    }

    /// Check if the stack is empty.
    pub fn isEmpty(self: *const Self) bool {
        return self.len == 0;
    }

    /// Check if the stack is full (at maximum capacity).
    pub fn isFull(self: *const Self) bool {
        return self.len >= CAPACITY;
    }
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Stack: push and pop single value" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    const value = U256.fromU64(42);

    try stack.push(value);
    try expectEqual(1, stack.len);

    const popped = try stack.pop();
    try expectEqual(value, popped);
    try expectEqual(0, stack.len);
}

test "Stack: push and pop multiple values (LIFO order)" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(1));
    try stack.push(U256.fromU64(2));
    try stack.push(U256.fromU64(3));

    try expectEqual(U256.fromU64(3), try stack.pop());
    try expectEqual(U256.fromU64(2), try stack.pop());
    try expectEqual(U256.fromU64(1), try stack.pop());
}

test "Stack: push to full stack returns StackOverflow" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    // Fill stack to capacity
    var i: usize = 0;
    while (i < Stack.CAPACITY) : (i += 1) {
        try stack.push(U256.fromU64(@intCast(i)));
    }

    // Next push should fail
    try expectError(error.StackOverflow, stack.push(U256.ZERO));
}

test "Stack: pop from empty stack returns StackUnderflow" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try expectError(error.StackUnderflow, stack.pop());
}

test "Stack: peek with invalid index returns StackUnderflow" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(42));
    try stack.push(U256.fromU64(43));

    try expectEqual(U256.fromU64(42), try stack.peek(1));
    try expectError(error.StackUnderflow, stack.peek(2));
    try expectError(error.StackUnderflow, stack.peek(100));
}

test "Stack: peek does not modify stack" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(1));
    try stack.push(U256.fromU64(2));
    try stack.push(U256.fromU64(3));

    try expectEqual(U256.fromU64(3), try stack.peek(0));
    try expectEqual(U256.fromU64(2), try stack.peek(1));
    try expectEqual(U256.fromU64(1), try stack.peek(2));
    try expectEqual(3, stack.len);
}

test "Stack: dup1 duplicates top item" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(1));
    try stack.push(U256.fromU64(2));

    try stack.dup(1); // DUP1

    try expectEqual(3, stack.len);
    try expectEqual(U256.fromU64(2), try stack.pop());
    try expectEqual(U256.fromU64(2), try stack.pop());
    try expectEqual(U256.fromU64(1), try stack.pop());
}

test "Stack: dup16 duplicates 16th item" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    // Push 16 values
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        try stack.push(U256.fromU64(@intCast(i + 1)));
    }

    try stack.dup(16); // DUP16 - duplicates the 16th item (1)

    try expectEqual(17, stack.len);
    try expectEqual(U256.fromU64(1), try stack.pop());
}

test "Stack: dup with insufficient depth returns error" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(42));

    try expectError(error.StackUnderflow, stack.dup(2));
}

test "Stack: dup with invalid index returns error" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(42));

    try expectError(error.StackUnderflow, stack.dup(0));
    try expectError(error.StackUnderflow, stack.dup(17));
}

test "Stack: swap1 exchanges top two items" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(1));
    try stack.push(U256.fromU64(2));

    try stack.swap(1); // SWAP1

    try expectEqual(U256.fromU64(1), try stack.pop());
    try expectEqual(U256.fromU64(2), try stack.pop());
}

test "Stack: swap16 exchanges top with 17th item" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    // Push 17 values
    var i: usize = 0;
    while (i < 17) : (i += 1) {
        try stack.push(U256.fromU64(@intCast(i + 1)));
    }

    try stack.swap(16); // SWAP16 - exchanges positions 0 and 16

    try expectEqual(U256.fromU64(1), try stack.pop());
}

test "Stack: swap with insufficient depth returns error" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(42));

    try expectError(error.StackUnderflow, stack.swap(2));
}

test "Stack: swap with invalid index returns error" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try stack.push(U256.fromU64(42));

    try expectError(error.StackUnderflow, stack.swap(0));
    try expectError(error.StackUnderflow, stack.swap(17));
}

test "Stack: operations on empty stack" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    try expect(stack.isEmpty());
    try expectEqual(0, stack.len);
}

test "Stack: push maximum 256-bit value" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    const max = U256.MAX;

    try stack.push(max);
    try expectEqual(max, try stack.pop());
}

test "Stack: exactly 1024 items" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    // Push exactly 1024 items
    var i: usize = 0;
    while (i < Stack.CAPACITY) : (i += 1) {
        try stack.push(U256.fromU64(@intCast(i)));
    }

    try expect(stack.isFull());
    try expectEqual(Stack.CAPACITY, stack.len);

    // Can still pop
    _ = try stack.pop();
    try expect(!stack.isFull());
}

test "Stack: all DUP variants (DUP1-DUP16)" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    // Push 16 distinct values
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        try stack.push(U256.fromU64(@intCast(i + 100)));
    }

    // Test each DUP variant
    var dup_idx: usize = 1;
    while (dup_idx <= 16) : (dup_idx += 1) {
        const initial_len = stack.len;
        try stack.dup(dup_idx);
        try expectEqual(initial_len + 1, stack.len);

        // The duplicated value should be from position dup_idx-1
        const expected_value = U256.fromU64(@intCast(116 - dup_idx));
        const actual_value = try stack.pop();
        try expectEqual(expected_value, actual_value);
    }
}

test "Stack: all SWAP variants (SWAP1-SWAP16)" {
    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    // Test each SWAP variant individually
    var swap_idx: usize = 1;
    while (swap_idx <= 16) : (swap_idx += 1) {
        // Clear stack for fresh test
        while (!stack.isEmpty()) {
            _ = try stack.pop();
        }

        // Push enough values to test this SWAP
        var i: usize = 0;
        while (i <= swap_idx) : (i += 1) {
            try stack.push(U256.fromU64(@intCast(i)));
        }

        // Perform swap
        try stack.swap(swap_idx);

        // Top should now be the value that was at position swap_idx
        const top = try stack.peek(0);
        try expectEqual(U256.fromU64(0), top);
    }
}

test "Stack: random operations maintain invariants" {
    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    var stack = try Stack.init(testing.allocator);
    defer stack.deinit();

    // Perform random push/pop operations
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        if (random.boolean()) {
            if (!stack.isFull()) try stack.push(U256.fromU64(random.int(u64)));
        } else {
            if (!stack.isEmpty()) _ = try stack.pop();
        }

        // Invariants:
        try expect(stack.len <= Stack.CAPACITY);
        try expectEqual(stack.len == 0, stack.isEmpty());
        try expectEqual(stack.len >= Stack.CAPACITY, stack.isFull());
    }
}
