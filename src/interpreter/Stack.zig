//! EVM stack implementation.
//!
//! The EVM uses a stack-based architecture with a maximum depth of 1024 items.
//! Each item on the stack is a 256-bit word (U256).

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const U256 = @import("../primitives/big.zig").U256;

const Stack = @This();

/// Heap-allocated array (preallocated to capacity).
data: []U256,

/// Current number of items on the stack.
len: usize,

/// Allocator for cleanup.
allocator: Allocator,

/// Maximum stack capacity as defined by the Ethereum specification.
/// This matches spec.stack_limit (default 1024).
pub const CAPACITY: usize = 1024;

/// Errors that can occur during stack operations.
pub const Error = error{
    StackOverflow,
    StackUnderflow,
    CastOverflow,
};

/// Initialize a new stack with the given allocator.
///
/// Pre-allocates capacity for `STACK_LIMIT` items to avoid reallocation.
pub fn init(allocator: Allocator) !Stack {
    const data = try allocator.alloc(U256, CAPACITY);
    return Stack{
        .data = data,
        .len = 0,
        .allocator = allocator,
    };
}

/// Free the stack's memory.
///
/// Must be called when done with the stack.
pub fn deinit(self: *Stack) void {
    self.allocator.free(self.data);
}

/// Push a value onto the stack.
///
/// Returns `error.StackOverflow` if stack is full.
pub fn push(self: *Stack, value: U256) Error!void {
    if (self.len >= CAPACITY)
        return error.StackOverflow;

    self.data[self.len] = value;
    self.len += 1;
}

/// Pop a value from the stack.
///
/// Returns `error.StackUnderflow` if stack is empty.
pub fn pop(self: *Stack) Error!U256 {
    if (self.len == 0)
        return error.StackUnderflow;

    self.len -= 1;
    return self.data[self.len];
}

/// Pop value and convert to target type.
pub fn popAs(self: *Stack, comptime T: type) Error!T {
    return u256To(try self.pop(), T);
}

/// Peek at the value at the given index from the top.
///
/// Index 0 is the top of the stack, index 1 is second from top, etc.
/// Returns `error.StackUnderflow` if index is out of bounds.
pub fn peek(self: *const Stack, index: usize) Error!U256 {
    if (index >= self.len)
        return error.StackUnderflow;
    return self.data[self.len - 1 - index];
}

/// Get a mutable reference to the value at the given index from the top.
///
/// This enables the peek-mutate optimization in operation handlers,
/// avoiding an extra pop+push by mutating the value in place.
pub fn peekMut(self: *Stack, index: usize) Error!*U256 {
    if (index >= self.len)
        return error.StackUnderflow;
    return &self.data[self.len - 1 - index];
}

/// Peek at value at index and convert to target type.
pub fn peekAs(self: *const Stack, index: usize, comptime T: type) Error!T {
    return u256To(try self.peek(index), T);
}

/// Duplicate the value at the given index from the top (1-16).
///
/// Returns `error.StackUnderflow` if index is invalid or out of bounds.
pub fn dup(self: *Stack, index: usize) Error!void {
    if (index == 0 or index > 16) {
        return error.StackUnderflow;
    }
    const value = try self.peek(index - 1);
    try self.push(value);
}

/// Swap the top value with the value at the given index (1-16).
///
/// Returns `error.StackUnderflow` if index is invalid or out of bounds.
pub fn swap(self: *Stack, index: usize) Error!void {
    if (index == 0 or index > 16 or index >= self.len)
        return error.StackUnderflow;

    const top_idx = self.len - 1;
    const swap_idx = self.len - 1 - index;
    std.mem.swap(U256, &self.data[top_idx], &self.data[swap_idx]);
}

/// Check if the stack is empty.
pub fn isEmpty(self: *const Stack) bool {
    return self.len == 0;
}

/// Check if the stack is full (at maximum capacity).
pub fn isFull(self: *const Stack) bool {
    return self.len >= CAPACITY;
}

/// Compare two stacks for equality.
///
/// Returns true if both stacks have the same depth and all values match in order.
/// Useful for testing expected stack states.
pub fn eql(self: *const Stack, other: *const Stack) bool {
    if (self.len != other.len) return false;

    var i: usize = 0;
    while (i < self.len) : (i += 1) {
        if (!self.data[i].eql(other.data[i])) return false;
    }

    return true;
}

/// Pop n values with type conversion.
///
/// Target type can be given as a single type (if all popped items have the same type), or by
/// listing all types explicitly.
///
/// All values have the same type:
/// ```zig
/// const dest, const src, const length = try stack.popN(3, usize);
/// ```
///
/// Mixed types:
/// ```zig
/// const offset, const value = try stack.popN(2, .{ usize, U256 });
/// ```
pub inline fn popN(self: *Stack, comptime n: usize, comptime types: anytype) Error!PopResult(n, types) {
    var result: PopResult(n, types) = undefined;

    inline for (0..n) |i| {
        const value = try self.pop();
        @field(result, std.fmt.comptimePrint("{d}", .{i})) = try u256To(value, typeAt(types, i));
    }

    return result;
}

/// Pop n-1 values with conversion, get dereferenced top value and mutable pointer to that top value.
///
/// Useful for operations that need to read and modify the top stack value in place.
///
/// Usage:
/// ```zig
/// const offset, const size, const size_ptr = try stack.popPeekN(2, usize);
/// // size is already converted by dereferencing size_ptr (no extra pop!)
/// size_ptr.* = computed_value;  // Modify top in place
/// ```
pub inline fn popPeekN(self: *Stack, comptime n: usize, comptime types: anytype) Error!PopPeekResult(n, types) {
    var result: PopPeekResult(n, types) = undefined;

    // Pop n-1 values with type conversion.
    inline for (0..n - 1) |i| {
        const value = try self.pop();
        @field(result, std.fmt.comptimePrint("{d}", .{i})) = try u256To(value, typeAt(types, i));
    }

    // Get pointer and dereference for top value.
    const top_ptr = try self.peekMut(0);
    @field(result, std.fmt.comptimePrint("{d}", .{n - 1})) = try u256To(top_ptr.*, typeAt(types, n - 1));
    @field(result, std.fmt.comptimePrint("{d}", .{n})) = top_ptr;

    return result;
}

/// Convert U256 to target type or return error.CastOverflow.
inline fn u256To(value: U256, comptime T: type) Error!T {
    return switch (T) {
        U256 => value,
        usize => value.toUsize() orelse return error.CastOverflow,
        u64 => value.toU64() orelse return error.CastOverflow,
        else => @compileError("unsupported type: " ++ @typeName(T)),
    };
}

/// Get type at index i from types. Single type: returns same type for all i. Tuple: returns types[i].
fn typeAt(comptime types: anytype, comptime i: usize) type {
    return if (@TypeOf(types) == type) types else types[i];
}

/// Validate types: if tuple, must have exactly n elements.
fn validateTypes(comptime n: usize, comptime types: anytype) void {
    const Types = @TypeOf(types);
    if (Types != type) {
        const info = @typeInfo(Types);
        if (info != .@"struct" or !info.@"struct".is_tuple)
            @compileError("expected type or tuple of types, got " ++ @typeName(Types));
        if (info.@"struct".fields.len != n)
            @compileError(std.fmt.comptimePrint("expected {d} types but got {d}", .{ n, info.@"struct".fields.len }));
    }
}

/// Build a struct field definition.
inline fn makeField(comptime name: [:0]const u8, comptime T: type) std.builtin.Type.StructField {
    return .{
        .name = name,
        .type = T,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(T),
    };
}

/// Generate return type for popAs: tuple of n converted values.
fn PopResult(comptime n: usize, comptime types: anytype) type {
    validateTypes(n, types);
    var fields: [n]std.builtin.Type.StructField = undefined;
    inline for (0..n) |i| {
        fields[i] = makeField(std.fmt.comptimePrint("{d}", .{i}), typeAt(types, i));
    }
    return @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}

/// Generate return type for popAsPeek: tuple of n converted values + `*U256` pointer.
fn PopPeekResult(comptime n: usize, comptime types: anytype) type {
    if (n < 1) @compileError("popAsPeek requires n >= 1");
    validateTypes(n, types);
    var fields: [n + 1]std.builtin.Type.StructField = undefined;
    inline for (0..n) |i| {
        fields[i] = makeField(std.fmt.comptimePrint("{d}", .{i}), typeAt(types, i));
    }
    fields[n] = makeField(std.fmt.comptimePrint("{d}", .{n}), *U256);
    return @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = true } });
}

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

test "Stack: eql" {
    const test_cases = [_]struct {
        name: []const u8,
        stack1_values: []const u64,
        stack2_values: []const u64,
        expected_equal: bool,
    }{
        .{
            .name = "both empty",
            .stack1_values = &[_]u64{},
            .stack2_values = &[_]u64{},
            .expected_equal = true,
        },
        .{
            .name = "identical single value",
            .stack1_values = &[_]u64{42},
            .stack2_values = &[_]u64{42},
            .expected_equal = true,
        },
        .{
            .name = "identical multiple values",
            .stack1_values = &[_]u64{ 42, 100 },
            .stack2_values = &[_]u64{ 42, 100 },
            .expected_equal = true,
        },
        .{
            .name = "different depths (1 vs 0)",
            .stack1_values = &[_]u64{42},
            .stack2_values = &[_]u64{},
            .expected_equal = false,
        },
        .{
            .name = "different depths (1 vs 2)",
            .stack1_values = &[_]u64{42},
            .stack2_values = &[_]u64{ 42, 43 },
            .expected_equal = false,
        },
        .{
            .name = "different values (same depth)",
            .stack1_values = &[_]u64{42},
            .stack2_values = &[_]u64{43},
            .expected_equal = false,
        },
        .{
            .name = "different values (multiple)",
            .stack1_values = &[_]u64{ 42, 100 },
            .stack2_values = &[_]u64{ 42, 99 },
            .expected_equal = false,
        },
        .{
            .name = "order matters",
            .stack1_values = &[_]u64{ 1, 2 },
            .stack2_values = &[_]u64{ 2, 1 },
            .expected_equal = false,
        },
    };

    for (test_cases) |tc| {
        var stack1 = try Stack.init(testing.allocator);
        defer stack1.deinit();
        var stack2 = try Stack.init(testing.allocator);
        defer stack2.deinit();

        for (tc.stack1_values) |value| {
            try stack1.push(U256.fromU64(value));
        }
        for (tc.stack2_values) |value| {
            try stack2.push(U256.fromU64(value));
        }

        if (tc.expected_equal) {
            try expect(stack1.eql(&stack2));
        } else {
            try expect(!stack1.eql(&stack2));
        }
    }
}
