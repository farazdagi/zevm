# Gas Module

EVM gas accounting and cost calculations.

## Overview

This module provides a clean, layered architecture for managing EVM gas costs across all Ethereum hard forks. It handles everything from static opcode costs to complex fork-dependent calculations to runtime gas tracking.

## Module Structure

The gas subsystem is organized into four focused modules:

```
gas/
├── costs.zig       -> Constants: Static u64 cost assignments (e.g. ADD = 3, PUSH0 = 2)
├── cost_types.zig  -> Types: Tagged unions for complex cost models (e.g. SstoreCost)
├── cost_fns.zig    -> Functions: Pure calculation logic (e.g. expCost, calldataCost)
├── accounting.zig  -> State: Runtime gas tracking (Gas struct)
└── mod.zig         -> Entry point: Clean public API
```

Note: functions in `cost_fn.zig` are exposed as `gas.Calculator` (in `interpreter/gas/mod.zig`).

When adding new gas-related code, ask:

```
Is it a fixed cost assignment?
├─ Yes -> costs.zig constant
│
Is it a simple value that transitions (10->50)?
├─ Yes -> Spec field (access directly: spec.field_name)
│
Does it need calculation logic or fork checks?
├─ Yes -> Spec field + Calculator function
│
Does the calculation logic change across forks?
├─ Yes -> cost_types.zig tagged union
│
Is it runtime state (limit, used, refunded)?
├─ Yes -> accounting.zig method
│
Is it a stateful calculation (depends on Gas state)?
└─ Yes -> accounting.zig method (e.g., memoryExpansionCost)
```

## Stateful Gas Methods

The `Gas` struct contains calculation methods that depend on runtime state:

- **`memoryExpansionCost(old_size, new_size)`** - Calculates incremental memory cost
  - Depends on `self.last_memory_cost` (tracked state)
  - Returns only the delta cost since last expansion
  - Justified exception to "calculations in Calculator" rule

- **`updateMemoryCost(memory_size)`** - Updates tracked memory cost
  - Called after successful memory expansion
  - Maintains state for next incremental calculation

These methods belong in `Gas` because they manage state across operations. Pure calculation logic (like `memoryCost()` for absolute cost) lives in `cost_fns.zig`.

## Usage

### Accessing Static Costs

```zig
const gas = @import("gas/mod.zig");

// Direct constant access
const add_cost = gas.Costs.ADD;  // 3
const push0_cost = gas.Costs.PUSH0;  // 2
```

### Fork-Dependent Calculations

```zig
const gas = @import("gas/mod.zig");

// Pure functions taking Spec as parameter
const exp_cost = gas.Calculator.expCost(spec, exponent_byte_len);
const calldata_cost = gas.Calculator.calldataCost(spec, data);
const sload_cost = gas.Calculator.sloadCost(spec, is_cold);
```

### Runtime Gas Tracking

```zig
const gas = @import("gas/mod.zig");

// Create Gas instance
var g = gas.Gas.init(100000, spec);

// Consume gas
try g.consume(gas.Costs.ADD);  // 3 gas

// Track refunds
g.refund(spec.sstore_clears_schedule);

// Get remaining
const remaining = g.remaining();
const with_refund = g.remainingWithRefund();
```

### Direct Spec Access

```zig
// Access fork-specific cost values directly from spec
const cold_cost = spec.cold_sload_cost;
const warm_cost = spec.warm_storage_read_cost;
const refund_amount = spec.sstore_clears_schedule;

// Use in gas operations
try g.consume(spec.cold_account_access_cost);
g.refund(spec.sstore_clears_schedule);

// Can also access through Gas instance
const cost_from_gas = g.spec.cold_sload_cost;
```

### Complex Cost Types

```zig
const gas = @import("gas/mod.zig");

// Access complex cost model (when implemented)
const sstore_cost = spec.sstore_cost;  // SstoreCost union
switch (sstore_cost) {
    .simple => |costs| { ... },
    .net_metered => |costs| { ... },
    .with_cold_access => |costs| { ... },
}
```

