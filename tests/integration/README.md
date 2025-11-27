# Integration Tests

This directory contains integration tests.

## Running Tests

```bash
# Run all integration tests
zig build test -Dtest-target=integration

# Run a specific test file
zig build test -Dtest-target=tests/integration/evm/calls.zig

# Run tests matching a pattern
zig build test -Dtest-target=integration -- gas::
```

