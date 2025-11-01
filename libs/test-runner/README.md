# Zig Test Runner

A custom test runner for Zig that provides Rust-like test output with colored status indicators, detailed test results, and filtering capabilities.

## Quick Start

```bash
# Run all tests
zig build test

# Run tests in a specific file
zig build test -Dfilter=primitives.address

# Run a specific test in `lib.zig`
zig build test -Dfilter="lib::basic"

# Show timing + filter
zig build test -Dfilter=address -Dtiming
```

## Features

- **Rust-like output format**: Clean, readable test output similar to Rust's test framework
- **Automatic test suite identification**: Automatically detects and shows which module is being tested (e.g., `lib`, `main`)
- **Clean module path display**: Shows test location from `src/` with `::` separator (e.g., `primitives.address::my_test`)
- **Flexible test filtering**: Filter tests by name using `-D` flags, `-- args` or environment variables
- **Colored status indicators**: Visual feedback with color-coded test results
  - Green `ok` for passing tests
  - Red `FAILED` for failing tests
  - Yellow `ignored` for skipped tests
  - Purple `LEAK` for memory leaks
- **Slowest test tracking**: Displays tests that exceed 1s threshold with note indicating the limit
- **Failure summary**: Detailed failure information at the end of test runs
- **Fail-first mode**: Stop on the first test failure for faster debugging
- **Memory leak detection**: Tracks and reports memory leaks using Zig's testing allocator
- **Test timing**: Optional timing information for each test

## Installation


In your project's `build.zig`, add the test runner module:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Define test runner options (these become -D flags)
    const test_filter = b.option([]const u8, "filter", "Filter tests by name");
    const test_timing = b.option(bool, "timing", "Show timing for each test") orelse false;
    const test_fail_first = b.option(bool, "fail-first", "Stop on first test failure") orelse false;

    // Your existing code...

    // Create tests with custom runner
    const tests = b.addTest(.{
        .root_module = your_module,
        .test_runner = .{
            .path = b.path("libs/test-runner/runner.zig"),
            .mode = .simple,
        },
    });

    // Create and run the test step
    const run_tests = b.addRunArtifact(tests);

    // Pass build options to test runner (enables -D flags without --)
    if (test_filter) |filter| {
        run_tests.addArg("--filter");
        run_tests.addArg(filter);
    }
    if (test_timing) {
        run_tests.addArg("--timing");
    }
    if (test_fail_first) {
        run_tests.addArg("--fail-first");
    }

    // Also forward any direct command-line arguments (enables -- syntax)
    if (b.args) |args| {
        run_tests.addArgs(args);
    }

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
```

## Usage

### Running Tests

**Recommended: Using `-D` flags:**

```bash
# Run all tests
zig build test

# Filter tests by module (all tests in a file)
zig build test -Dfilter=primitives.address

# Filter by module using :: separator
zig build test -Dfilter="lib::"

# Filter by specific test in a module
zig build test -Dfilter="primitives.address::Address"

# Filter by test name across all modules
zig build test -Dfilter="::basic"

# Show timing for each test
zig build test -Dtiming

# Stop on first failure
zig build test -Dfail-first

# Combine multiple flags
zig build test -Dfilter=primitives -Dtiming -Dfail-first
```

**Alternative: Using `--` separator (more similar to `cargo test`):**

```bash
# Filter tests (three equivalent ways)
zig build test -- address              # Positional argument
zig build test -- --filter address     # With --filter flag
zig build test -- --filter=address     # With --filter= format

# With other flags
zig build test -- --timing --fail-first
zig build test -- primitives --timing
```

**Using environment variables:**

```bash
TEST_FILTER=address zig build test
TEST_TIMING=true zig build test
TEST_FAIL_FIRST=true zig build test
```

### Configuration Options

Options can be set in three ways (in order of precedence):
1. **Build flags** (`-D` flags) - Recommended, integrated with Zig's build system
2. **Command-line arguments** (after `--` separator) - For runtime arguments to test executable
3. **Environment variables** - For CI/CD environments

**Available Options:**

| Build Flag | CLI Argument | Env Variable | Description |
|------------|-------------|--------------|-------------|
| `-Dfilter=<value>` | `--filter=<value>` or positional | `TEST_FILTER` | Filter tests by substring |
| `-Dtiming` | `--timing` | `TEST_TIMING=true` | Show timing for each test |
| `-Dfail-first` | `--fail-first` | `TEST_FAIL_FIRST=true` | Stop on first test failure |
| - | - | `TEST_SHOW_IGNORED=true` | Include ignored tests (env only) |

**View all options:**
```bash
zig build --help
```

### Test Filtering

The filter applies to the full test path (module + test name) as displayed in the output. This mimics Rust's test filtering behavior.

**Filter Format:**

Tests are displayed as: `module.path::test_name`

Examples:
- `lib::test_0` - unnamed test in lib module
- `lib::basic add functionality` - named test in lib module
- `primitives.address::Address.fromHexString runtime` - test in nested module

**Filtering Examples:**

| Filter | Matches | Example |
|--------|---------|---------|
| `primitives.address` | All tests in `src/primitives/address.zig` | Runs all tests in that file |
| `lib::` | All tests in lib module | Uses `::` as module/test separator |
| `primitives.address::Address` | Tests starting with "Address" in that module | Partial test name match |
| `::basic` | Any test containing "basic" across all modules | Cross-module search |
| `address` | Any test or module containing "address" | Matches both module and test names |

**Real Examples:**

```bash
# Run all tests in src/primitives/address.zig
zig build test -Dfilter=primitives.address

# Run specific test by full path
zig build test -Dfilter="primitives.address::Address.fromHexString"

# Run all tests in src/lib.zig
zig build test -Dfilter="lib::"

# Run all tests with "add" in the name, any module
zig build test -Dfilter=add
```

**Note:** The filter is a substring match applied to the full formatted test path, just like `cargo test` in Rust.


## Comparison with Default Zig Test Runner

The default Zig test runner provides minimal output. This custom runner adds:

- **Rust-like output**: Individual test status lines with module paths
- **Intuitive filtering**: Filter by module path or test name, just like `cargo test`
- **Clean path display**: Uses `::` separator between module and test name
- **Colored output**: Better visual feedback with color-coded results
- **Failure summary**: Detailed section showing all failures at the end
- **Performance tracking**: Shows tests exceeding 1s threshold with note indicating the limit
- **Flexible configuration**: `-D` flags, `--` arguments, or environment variables
- **Detailed statistics**: Shows passed, failed, ignored, leaked, and filtered counts

