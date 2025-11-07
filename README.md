# Zevm

Zig implementation of the Ethereum Virtual Machine (EVM).

## Testing

Run tests using `zig build test`. 

The project has three test suites: library unit tests (`lib`), executable tests (`main`), and integration tests (located in `tests/`).

### Run specific test suites

```bash
# Run only library tests
zig build test -Dtest-target=lib

# Run only executable tests
zig build test -Dtest-target=main

# Run all integration tests
zig build test -Dtest-target=integration

# Run specific integration test file
zig build test -Dtest-target=tests/big.zig
```

### Filter tests by name

```bash
# Combine suite selection with filtering
zig build test -Dtest-target=lib -Dfilter=address

# Alternative syntax (--test-target also works with --)
zig build test -- --test-target=lib address::

# Filter tests (works across all suites)
zig build test -- address::
```

### Default behavior

```bash
# Run all tests (default)
zig build test
```

## Benchmarking

Run benchmarks using `zig build bench`. Benchmark files are located in the `bench/` directory and are automatically discovered by the build system.

### Run all benchmarks

```bash
# Run all benchmarks (default, Debug mode)
zig build bench
```

### Run specific benchmarks

```bash
# Run only the stack benchmark
zig build bench -Dbench-target=stack

# Run only the big integer benchmark
zig build bench -Dbench-target=big

# Alternative: specify with .zig extension
zig build bench -Dbench-target=stack.zig
```

### Optimization modes

By default, benchmarks run in Debug mode to prevent over-optimization of benchmark loops. You can specify different optimization levels:

```bash
# Run with full optimizations
zig build bench -Dbench-optimize=ReleaseFast

# Run specific benchmark with optimizations
zig build bench -Dbench-target=stack -Dbench-optimize=ReleaseFast
```
