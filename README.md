# Zevm

Zig implementation of the Ethereum Virtual Machine (EVM).

## Testing

Run tests using `zig build test`. The project has three test suites: library tests (`lib`), executable tests (`main`), and integration tests (located in `tests/`).

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
# Filter tests (works across all suites)
zig build test -- address::

# Combine suite selection with filtering
zig build test -Dtest-target=lib -Dfilter=address

# Alternative syntax (--test-target also works with --)
zig build test -- --test-target=lib address::
```

### Default behavior

```bash
# Run all tests (default)
zig build test
```
