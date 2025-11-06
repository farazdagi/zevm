const std = @import("std");
const U256 = @import("zevm").primitives.U256;

pub fn main() !void {
    std.debug.print("\n=== U256 Multiplication Benchmark ===\n\n", .{});

    try benchmarkMul();

    std.debug.print("\n", .{});
}

fn benchmarkMul() !void {
    const Timer = std.time.Timer;

    // Test data: various multiplication patterns
    const test_cases = [_]struct {
        name: []const u8,
        a: U256,
        b: U256,
    }{
        .{
            .name = "small * small",
            .a = U256.fromU64(12345),
            .b = U256.fromU64(67890),
        },
        .{
            .name = "large * small",
            .a = U256.MAX,
            .b = U256.fromU64(42),
        },
        .{
            .name = "mid * mid",
            .a = U256.fromU128(0x123456789ABCDEF0),
            .b = U256.fromU128(0xFEDCBA9876543210),
        },
        .{
            .name = "large * large",
            .a = U256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0x1234567890ABCDEF, 0xFEDCBA0987654321 } },
            .b = U256{ .limbs = .{ 0x1111111111111111, 0x2222222222222222, 0x3333333333333333, 0x4444444444444444 } },
        },
    };

    const iterations: u32 = 1_000_000;
    std.debug.print("Iterations per test: {}\n\n", .{iterations});

    for (test_cases) |tc| {
        var timer = try Timer.start();
        const start = timer.read();

        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = tc.a.mul(tc.b);
            // Prevent optimization
            std.mem.doNotOptimizeAway(&result);
        }

        const end = timer.read();
        const elapsed_ns = end - start;
        const ns_per_op = elapsed_ns / iterations;

        std.debug.print("{s:20}: {d:>6} ns/op ({d:.2} ms total)\n", .{
            tc.name,
            ns_per_op,
            @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0,
        });

        // Ensure result is used
        std.mem.doNotOptimizeAway(&result);
    }
}
