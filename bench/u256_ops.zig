const std = @import("std");
const U256 = @import("zevm").primitives.U256;

pub fn main() !void {
    std.debug.print("\n=== U256 Operations Benchmark ===\n\n", .{});

    try benchmarkArithmetic();
    try benchmarkComparisons();
    try benchmarkBitwise();
    try benchmarkShifts();

    std.debug.print("\n", .{});
}

fn benchmarkArithmetic() !void {
    const Timer = std.time.Timer;
    const iterations: u32 = 1_000_000;

    std.debug.print("--- Arithmetic Operations ({} iterations) ---\n", .{iterations});

    // Test data
    const small_a = U256.fromU64(12345);
    const small_b = U256.fromU64(67890);
    const large_a = U256.MAX;
    const mid_a = U256.fromU128(0x123456789ABCDEF0);
    const mid_b = U256.fromU128(0xFEDCBA9876543210);

    // ADD benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = small_a.add(small_b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  ADD (small):      {d:>6} ns/op\n", .{ns_per_op});
    }

    // SUB benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = large_a.sub(small_b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  SUB (large):      {d:>6} ns/op\n", .{ns_per_op});
    }

    // MUL benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = mid_a.mul(mid_b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  MUL (mid):        {d:>6} ns/op\n", .{ns_per_op});
    }

    // DIV benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = large_a.div(small_b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  DIV (large/small):{d:>6} ns/op\n", .{ns_per_op});
    }

    // REM benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = large_a.rem(small_b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  REM (large %% small):{d:>6} ns/op\n", .{ns_per_op});
    }

    // ADDMOD benchmark
    {
        const modulus = U256.fromU64(1000000007); // prime modulus
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = mid_a.addmod(mid_b, modulus);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  ADDMOD:           {d:>6} ns/op\n", .{ns_per_op});
    }

    // MULMOD benchmark
    {
        const modulus = U256.fromU64(1000000007);
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = mid_a.mulmod(mid_b, modulus);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  MULMOD:           {d:>6} ns/op\n", .{ns_per_op});
    }

    // EXP benchmark (smaller iterations for slower operation)
    {
        const exp_iterations: u32 = 100_000;
        const base = U256.fromU64(3);
        const exponent = U256.fromU64(100);
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..exp_iterations) |_| {
            result = base.exp(exponent);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / exp_iterations;
        std.debug.print("  EXP (3^100):      {d:>6} ns/op (100k iter)\n", .{ns_per_op});
    }

    std.debug.print("\n", .{});
}

fn benchmarkComparisons() !void {
    const Timer = std.time.Timer;
    const iterations: u32 = 1_000_000;

    std.debug.print("--- Comparison Operations ({} iterations) ---\n", .{iterations});

    const a = U256.fromU128(0x123456789ABCDEF0);
    const b = U256.fromU128(0xFEDCBA9876543210);

    // EQL benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result: bool = false;
        for (0..iterations) |_| {
            result = a.eql(b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  EQL:              {d:>6} ns/op\n", .{ns_per_op});
    }

    // LT benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result: bool = false;
        for (0..iterations) |_| {
            result = a.lt(b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  LT:               {d:>6} ns/op\n", .{ns_per_op});
    }

    // GT benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result: bool = false;
        for (0..iterations) |_| {
            result = a.gt(b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  GT:               {d:>6} ns/op\n", .{ns_per_op});
    }

    // SLT benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result: bool = false;
        for (0..iterations) |_| {
            result = a.slt(b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  SLT:              {d:>6} ns/op\n", .{ns_per_op});
    }

    // SGT benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result: bool = false;
        for (0..iterations) |_| {
            result = a.sgt(b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  SGT:              {d:>6} ns/op\n", .{ns_per_op});
    }

    // ISZERO benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result: bool = false;
        for (0..iterations) |_| {
            result = a.isZero();
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  ISZERO:           {d:>6} ns/op\n", .{ns_per_op});
    }

    std.debug.print("\n", .{});
}

fn benchmarkBitwise() !void {
    const Timer = std.time.Timer;
    const iterations: u32 = 1_000_000;

    std.debug.print("--- Bitwise Operations ({} iterations) ---\n", .{iterations});

    const a = U256.fromU128(0x123456789ABCDEF0);
    const b = U256.fromU128(0xFEDCBA9876543210);

    // AND benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = a.bitAnd(b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  AND:              {d:>6} ns/op\n", .{ns_per_op});
    }

    // OR benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = a.bitOr(b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  OR:               {d:>6} ns/op\n", .{ns_per_op});
    }

    // XOR benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = a.bitXor(b);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  XOR:              {d:>6} ns/op\n", .{ns_per_op});
    }

    // NOT benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = a.bitNot();
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  NOT:              {d:>6} ns/op\n", .{ns_per_op});
    }

    // BYTE benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result: u8 = 0;
        for (0..iterations) |_| {
            result = a.byte(15);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  BYTE:             {d:>6} ns/op\n", .{ns_per_op});
    }

    std.debug.print("\n", .{});
}

fn benchmarkShifts() !void {
    const Timer = std.time.Timer;
    const iterations: u32 = 1_000_000;

    std.debug.print("--- Shift Operations ({} iterations) ---\n", .{iterations});

    const value = U256.fromU128(0x123456789ABCDEF0);

    // SHL benchmark (small shift)
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = value.shl(8);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  SHL (8 bits):     {d:>6} ns/op\n", .{ns_per_op});
    }

    // SHL benchmark (limb-aligned)
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = value.shl(64);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  SHL (64 bits):    {d:>6} ns/op\n", .{ns_per_op});
    }

    // SHR benchmark (small shift)
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = value.shr(8);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  SHR (8 bits):     {d:>6} ns/op\n", .{ns_per_op});
    }

    // SHR benchmark (limb-aligned)
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = value.shr(64);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  SHR (64 bits):    {d:>6} ns/op\n", .{ns_per_op});
    }

    // SAR benchmark
    {
        const neg_value = U256.MAX; // negative in two's complement
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = neg_value.sar(8);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  SAR (8 bits):     {d:>6} ns/op\n", .{ns_per_op});
    }

    // SIGNEXTEND benchmark
    {
        var timer = try Timer.start();
        const start = timer.read();
        var result = U256.ZERO;
        for (0..iterations) |_| {
            result = value.signExtend(7);
            std.mem.doNotOptimizeAway(&result);
        }
        const end = timer.read();
        const ns_per_op = (end - start) / iterations;
        std.debug.print("  SIGNEXTEND:       {d:>6} ns/op\n", .{ns_per_op});
    }

    std.debug.print("\n", .{});
}
