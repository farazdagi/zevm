const std = @import("std");
const zevm = @import("zevm");
const Stack = zevm.interpreter.Stack;
const U256 = zevm.primitives.U256;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Stack Benchmarks ===\n\n", .{});

    const iterations: usize = 1_000_000;
    var stack = try Stack.init(allocator);
    defer stack.deinit();

    // Warm up
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try stack.push(U256.fromU64(i));
        _ = try stack.pop();
    }

    // Benchmark push
    const start_push = std.time.nanoTimestamp();
    i = 0;
    while (i < Stack.CAPACITY) : (i += 1) {
        try stack.push(U256.fromU64(42));
    }
    const end_push = std.time.nanoTimestamp();
    const elapsed_push_ns = @as(u64, @intCast(end_push - start_push));

    // Benchmark pop
    const start_pop = std.time.nanoTimestamp();
    i = 0;
    while (i < Stack.CAPACITY) : (i += 1) {
        _ = try stack.pop();
    }
    const end_pop = std.time.nanoTimestamp();
    const elapsed_pop_ns = @as(u64, @intCast(end_pop - start_pop));

    // Benchmark push/pop cycle
    const start_cycle = std.time.nanoTimestamp();
    i = 0;
    while (i < iterations) : (i += 1) {
        if (!stack.isFull()) {
            try stack.push(U256.fromU64(42));
        } else {
            _ = try stack.pop();
        }
    }
    const end_cycle = std.time.nanoTimestamp();
    const elapsed_cycle_ns = @as(u64, @intCast(end_cycle - start_cycle));

    std.debug.print("Stack Operations (1024 items):\n", .{});
    std.debug.print("  Push:           {d:>6.2} ns/op\n", .{@as(f64, @floatFromInt(elapsed_push_ns)) / @as(f64, @floatFromInt(Stack.CAPACITY))});
    std.debug.print("  Pop:            {d:>6.2} ns/op\n", .{@as(f64, @floatFromInt(elapsed_pop_ns)) / @as(f64, @floatFromInt(Stack.CAPACITY))});
    std.debug.print("\nPush/Pop Cycle ({} iterations):\n", .{iterations});
    std.debug.print("  Mixed ops:      {d:>6.2} ns/op\n\n", .{@as(f64, @floatFromInt(elapsed_cycle_ns)) / @as(f64, @floatFromInt(iterations))});

    std.debug.print("Memory usage:\n", .{});
    std.debug.print("  Stack struct:   ~40 bytes\n", .{});
    std.debug.print("  Data array:     32,768 bytes (1024 × 32)\n", .{});
    std.debug.print("  Total:          ~32.8 KB per stack\n\n", .{});
}
