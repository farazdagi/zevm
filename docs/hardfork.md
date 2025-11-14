# Hardfork Specification System

## Overview

The hardfork specification system is the central configuration mechanism in Zevm. It defines, for each Ethereum hardfork:

- **Static gas costs** for all opcodes (computed at compile-time)
- **Dynamic gas cost functions** for operations with variable costs
- **Instruction handlers** that implement opcode behavior
- **Feature flags** and **limits** (EIP activation, blob counts, refund rules, etc.)

The system is designed to be:
- **Comptime-evaluated**: Zero runtime overhead for fork selection
- **Incremental**: Forks build on previous forks, only specifying changes
- **Extensible**: New forks added without modifying existing code
- **Type-safe**: Zig's comptime ensures correctness

## Fork Inheritance Model

### Hierarchical Fork Structure

Each hardfork builds on a previous fork, forming a chain from `FRONTIER` (genesis) to `PRAGUE` (latest):

```
FRONTIER (base)
  ↓
HOMESTEAD
  ↓
TANGERINE
  ↓
... (chain continues)
  ↓
CANCUN
  ↓
PRAGUE
```

Each `Spec` has a `base_fork` field that references its parent. Only `FRONTIER` has `base_fork = null`.

### Inheritance Mechanism

The `forkSpec()` helper function implements inheritance:

```zig
pub const LONDON = forkSpec(.LONDON, BERLIN, .{
    .max_refund_quotient = 5,      // EIP-3529: Changed from 2 to 5
    .sstore_clears_schedule = 4800, // EIP-3529: Reduced from 15000
    .has_basefee = true,            // EIP-3198
    .updateCosts = struct {
        fn f(table: *FixedGasCosts, spec: Spec) void {
            table.costs[@intFromEnum(Opcode.BASEFEE)] = FixedGasCosts.BASE;
        }
    }.f,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            table.table[@intFromEnum(Opcode.BASEFEE)] = .{ .execute = handlers.opBasefee };
        }
    }.f,
});
```

**How it works:**
1. Copies all fields from `BERLIN` spec
2. Sets `fork = .LONDON` and `base_fork = .BERLIN`
3. Applies only the changed fields from the changes struct
4. The result is a complete spec with all inherited configuration

### Comptime Resolution

When you request a spec for a fork, the system walks the inheritance chain at **compile-time**:

```zig
// User code
const spec = Spec.forFork(.LONDON);
const costs = spec.gasCosts();  // Returns FixedGasCosts for London
```

Internally, `FixedGasCosts.forFork(.LONDON)` iterates from `FRONTIER` → `HOMESTEAD` → ... → `LONDON`, applying each fork's `updateCosts` function in order. The final cost table is computed at **compile-time** and embedded in the binary.

## Static Gas Costs (FixedGasCosts)

### Overview

`FixedGasCosts` is a comptime-generated lookup table of base gas costs for all 256 possible opcodes.

**Location**: `src/gas/FixedGasCosts.zig`

### Cost Tiers

Standard cost constants used across operations:

```zig
pub const ZERO: u64 = 0;
pub const BASE: u64 = 2;
pub const VERYLOW: u64 = 3;
pub const LOW: u64 = 5;
pub const MID: u64 = 8;
pub const HIGH: u64 = 10;
pub const JUMPDEST: u64 = 1;
```

### Comptime Generation

Each fork defines an optional `updateCosts` function that modifies the cost table:

```zig
// FRONTIER defines base costs
pub const FRONTIER = Spec{
    // ...
    .updateCosts = struct {
        fn f(table: *FixedGasCosts, spec: Spec) void {
            _ = spec;
            table.costs[@intFromEnum(Opcode.ADD)] = FixedGasCosts.VERYLOW;
            table.costs[@intFromEnum(Opcode.MUL)] = FixedGasCosts.LOW;
            table.costs[@intFromEnum(Opcode.SLOAD)] = 50;
            // ... all other opcodes
        }
    }.f,
    // ...
};

// TANGERINE changes some costs (EIP-150)
pub const TANGERINE = forkSpec(.TANGERINE, HOMESTEAD, .{
    .cold_sload_cost = 200, // EIP-150
    .updateCosts = struct {
        fn f(table: *FixedGasCosts, spec: Spec) void {
            _ = spec;
            // Only specify changes
            table.costs[@intFromEnum(Opcode.SLOAD)] = 200; // Was 50
            table.costs[@intFromEnum(Opcode.BALANCE)] = 400; // Was 20
            table.costs[@intFromEnum(Opcode.CALL)] = 700; // Was 40
        }
    }.f,
});
```

**Key points:**
- `FRONTIER` initializes all costs
- Later forks only update changed costs
- `updateCosts` is optional (if `null`, no cost changes)
- The `spec` parameter allows fork-specific logic (e.g., using `spec.warm_storage_read_cost`)

### Usage

The interpreter fetches costs via the spec:

```zig
const base_cost = spec.gasCost(opcode_byte); // Inline lookup
try gas.consume(base_cost);
```

Since `spec` is known at compile-time, this resolves to a direct array access with zero overhead.

## Dynamic Gas Costs (DynamicGasCosts)

### Overview

Some operations have variable gas costs that depend on runtime values (memory expansion, exponent size, storage changes, etc.).

**Location**: `src/gas/DynamicGasCosts.zig`

### Current Implementation

Dynamic cost functions take runtime parameters and return the additional gas cost:

```zig
pub fn opExp(interp: *Interpreter) !u64 {
    const exponent = try interp.ctx.stack.peek(1);
    const exponent_byte_size = exponent.byteLength();
    const gas_per_byte: u64 = if (interp.spec.fork.isBefore(.SPURIOUS_DRAGON)) 10 else 50;
    return gas_per_byte * exponent_byte_size;
}

pub fn opMload(interp: *Interpreter) !u64 {
    const offset = try interp.ctx.stack.peek(0);
    const new_size = offset.addScalar(32);
    return accounting.memoryExpansionCost(interp.ctx.gas.memory_size, new_size);
}
```

**Current approach:**
- Functions contain fork-specific branching (e.g., `if (fork.isBefore(...))`)
- This works but couples cost logic to fork checks

### Future Implementation (Spec-Based Configuration)

> **Note**: This refactoring is planned but not yet implemented.

Instead of branching, move fork-specific values to `Spec` fields with defaults:

```zig
// In Spec struct
pub const Spec = struct {
    // ... existing fields ...

    // Dynamic cost parameters (with defaults)
    exp_byte_cost: u64 = 10, // Default for Frontier
    // ... other cost params ...
};

// SPURIOUS_DRAGON overrides the default
pub const SPURIOUS_DRAGON = forkSpec(.SPURIOUS_DRAGON, TANGERINE, .{
    .exp_byte_cost = 50, // EIP-160
});

// DynamicGasCosts becomes simpler
pub fn opExp(interp: *Interpreter) !u64 {
    const exponent = try interp.ctx.stack.peek(1);
    const exponent_byte_size = exponent.byteLength();
    return interp.spec.exp_byte_cost * exponent_byte_size; // No branching
}
```

**Benefits:**
- Eliminates runtime branching
- Makes fork-specific costs explicit in spec
- Easier to add new forks (just set fields)
- Zig's default values reduce boilerplate

### Assigning Dynamic Costs to Opcodes

Dynamic cost functions are assigned in `updateHandlers`:

```zig
.updateHandlers = struct {
    fn f(table: *InstructionTable) void {
        const t = &table.table;
        t[@intFromEnum(Opcode.EXP)] = .{
            .execute = handlers.opExp,
            .dynamicGasCost = DynamicGasCosts.opExp  // Assigned here
        };
        t[@intFromEnum(Opcode.MLOAD)] = .{
            .execute = handlers.opMload,
            .dynamicGasCost = DynamicGasCosts.opMload
        };
    }
}.f,
```

## Instruction Handlers (InstructionTable)

### Overview

`InstructionTable` is a comptime-generated jump table mapping opcodes (0x00-0xFF) to their handler functions.

**Location**: `src/interpreter/InstructionTable.zig`

### Instruction Entry

Each entry contains:

```zig
pub const Instruction = struct {
    execute: ?*const fn (*Interpreter) InterpreterError!void,
    dynamicGasCost: ?*const fn (*Interpreter) InterpreterError!u64,
    is_control_flow: bool = false,
};
```

- **`execute`**: The handler function that implements the opcode
- **`dynamicGasCost`**: Optional function for variable gas costs
- **`is_control_flow`**: Marks opcodes that alter PC (JUMP, RETURN, etc.)

### Comptime Generation

Like `FixedGasCosts`, forks incrementally build the instruction table:

```zig
// FRONTIER defines all base opcodes
pub const FRONTIER = Spec{
    // ...
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            t[@intFromEnum(Opcode.ADD)] = .{ .execute = handlers.opAdd };
            t[@intFromEnum(Opcode.MUL)] = .{ .execute = handlers.opMul };
            // ... all Frontier opcodes
        }
    }.f,
};

// SHANGHAI adds PUSH0 (EIP-3855)
pub const SHANGHAI = forkSpec(.SHANGHAI, MERGE, .{
    .has_push0 = true,
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            t[@intFromEnum(Opcode.PUSH0)] = .{ .execute = handlers.opPush0 };
        }
    }.f,
});
```

**Key points:**
- `FRONTIER` populates the entire table
- Later forks add new opcodes or replace existing ones
- `updateHandlers` is optional (if `null`, no handler changes)
- The same opcode can be replaced with a different implementation

### Fork-Specific Implementations

For complex operations like `SSTORE`, different forks can use entirely different handler functions:

```zig
// Hypothetical example (not actual code)

// Simple SSTORE for Frontier
fn opSstoreFrontier(interp: *Interpreter) !void {
    // Simple gas calculation
    const key = try interp.ctx.stack.pop();
    const value = try interp.ctx.stack.pop();
    try interp.host.sstore(interp.contract.address, key, value);
}

// Complex SSTORE for Berlin (EIP-2929: warm/cold access)
fn opSstoreBerlin(interp: *Interpreter) !void {
    // Complex gas calculation with warm/cold tracking
    const key = try interp.ctx.stack.pop();
    const value = try interp.ctx.stack.pop();
    const is_cold = !interp.accessed_storage_keys.contains(key);
    // ... complex gas logic ...
    try interp.host.sstore(interp.contract.address, key, value);
}

// FRONTIER uses simple version
pub const FRONTIER = Spec{
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            table.table[@intFromEnum(Opcode.SSTORE)] = .{
                .execute = opSstoreFrontier,
                .dynamicGasCost = DynamicGasCosts.opSstoreFrontier,
            };
        }
    }.f,
};

// BERLIN uses complex version
pub const BERLIN = forkSpec(.BERLIN, ISTANBUL, .{
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            table.table[@intFromEnum(Opcode.SSTORE)] = .{
                .execute = opSstoreBerlin,
                .dynamicGasCost = DynamicGasCosts.opSstoreBerlin,
            };
        }
    }.f,
});
```

This allows completely different implementations per fork without any runtime branching.

## Configuration Fields

### Overview

Beyond costs and handlers, `Spec` contains many configuration fields that control EVM behavior:

```zig
pub const Spec = struct {
    fork: Hardfork,
    base_fork: ?Hardfork,

    // Gas and refund parameters
    max_refund_quotient: u64,       // EIP-3529: refund cap
    sstore_clears_schedule: u64,    // SSTORE refund amount
    cold_sload_cost: u64,           // EIP-2929: cold storage access
    warm_storage_read_cost: u64,    // EIP-2929: warm storage access

    // Limits
    max_initcode_size: ?usize,      // EIP-3860: init code limit
    max_code_size: usize,           // EIP-170: code size limit

    // Feature flags (EIP activation)
    has_push0: bool,                // EIP-3855: PUSH0 instruction
    has_basefee: bool,              // EIP-3198: BASEFEE opcode
    has_prevrandao: bool,           // EIP-4399: PREVRANDAO
    has_tstore: bool,               // EIP-1153: transient storage
    has_mcopy: bool,                // EIP-5656: MCOPY instruction
    has_blob_opcodes: bool,         // EIP-4844: blob operations

    // Blob parameters
    target_blobs_per_block: u8,     // EIP-4844/7691
    max_blobs_per_block: u8,

    // ... more fields
};
```

### Usage in Code

Feature flags control opcode availability:

```zig
// In interpreter
if (opcode == @intFromEnum(Opcode.PUSH0) and !spec.has_push0) {
    return error.InvalidOpcode; // PUSH0 not available pre-Shanghai
}
```

Cost parameters are used in gas calculations:

```zig
// In dynamic gas cost
if (is_cold_access) {
    cost += spec.cold_sload_cost;
} else {
    cost += spec.warm_storage_read_cost;
}
```

## Adding a New Fork

### Step-by-Step Guide

1. **Add enum variant** to `Hardfork`:

```zig
pub const Hardfork = enum(u8) {
    // ... existing forks ...
    CANCUN = 17,
    PRAGUE = 18,
    OSAKA = 19,  // <- New fork
};
```

2. **Define the spec** using `forkSpec()`:

```zig
/// Osaka (Q4, 2025)
///
/// EIP-XXXX: New feature description
/// EIP-YYYY: Another feature
pub const OSAKA = forkSpec(.OSAKA, PRAGUE, .{
    // Change configuration fields
    .some_new_limit = 1000,
    .has_new_feature = true,

    // Optionally update costs
    .updateCosts = struct {
        fn f(table: *FixedGasCosts, spec: Spec) void {
            _ = spec;
            // Modify costs
            table.costs[@intFromEnum(Opcode.SOME_OP)] = 50;
        }
    }.f,

    // Optionally update handlers
    .updateHandlers = struct {
        fn f(table: *InstructionTable) void {
            const t = &table.table;
            // Add new opcode
            t[@intFromEnum(Opcode.NEW_OP)] = .{ .execute = handlers.opNewOp };
            // Or replace existing
            t[@intFromEnum(Opcode.OLD_OP)] = .{ .execute = handlers.opOldOpOptimized };
        }
    }.f,
});
```

3. **Update `Spec.forFork()`**:

```zig
pub fn forFork(fork: Hardfork) Spec {
    return switch (fork) {
        // ... existing cases ...
        .PRAGUE => PRAGUE,
        .OSAKA => OSAKA,  // <- Add new case
    };
}
```

4. **Update `Hardfork.name()`** (optional, for display):

```zig
pub fn name(self: Hardfork) []const u8 {
    return switch (self) {
        // ... existing cases ...
        .OSAKA => "Osaka",
    };
}
```

5. **Implement new opcodes** (if any) in `src/interpreter/handlers/`:

```zig
// src/interpreter/handlers/new_feature.zig
pub fn opNewOp(interp: *Interpreter) !void {
    // Implementation
}
```

6. **Add tests**:

```zig
test "Spec: Osaka has new feature" {
    const osaka = OSAKA;
    try expect(osaka.has_new_feature);
    try expectEqual(1000, osaka.some_new_limit);
}

test "Spec: Osaka gas costs" {
    const costs = OSAKA.gasCosts();
    try expectEqual(50, costs.costs[@intFromEnum(Opcode.SOME_OP)]);
}
```

**That's it!** The comptime system automatically:
- Inherits all configuration from PRAGUE
- Applies your changes
- Generates the correct cost and instruction tables
- Makes them available at zero runtime cost

## Design Principles

### 1. Comptime Evaluation

All fork selection happens at **compile-time**:
- No runtime branching for fork checks
- No virtual dispatch or function pointers
- Optimal machine code generated per fork
- Binary can be specialized for a single fork if desired

### 2. Data-Oriented Design

Configuration is data, not code:
- Spec is a plain struct with fields
- Costs are arrays indexed by opcode
- Handlers are direct function pointers
- Cache-friendly, CPU-efficient

### 3. Incremental Definition

Forks only specify **changes** from their base:
- Reduces duplication
- Makes fork differences explicit
- Easy to audit what changed in each fork
- Natural mapping to EIP descriptions

### 4. Extensibility

The system supports:
- **New forks**: Add enum variant + define spec
- **New opcodes**: Add to instruction table
- **Cost changes**: Update cost table or add dynamic function
- **Feature flags**: Add boolean field to Spec
- **Complex changes**: Replace entire handler implementations

### 5. Type Safety

Zig's type system ensures:
- All opcodes have valid handlers (or are explicitly unimplemented)
- All cost lookups are bounds-checked
- Fork configurations are complete (missing fields = compile error)
- No runtime type errors

## Current Limitations & Future Work

### Chain Extensibility (Future Sprint)

The current system supports Ethereum mainnet forks (Frontier → Prague). Support for **L2 chains** (Optimism, Arbitrum, Polygon, etc.) is planned:

**Approach:**
1. Extend `Hardfork` enum with chain-specific variants:
   ```zig
   pub const Hardfork = enum(u8) {
       // Ethereum mainnet
       FRONTIER = 0, ..., PRAGUE = 18,
       // Optimism
       OPTIMISM_BEDROCK = 100,
       OPTIMISM_CANYON = 101,
       OPTIMISM_ECOTONE = 102,
       // ... other chains
   };
   ```

2. Add optional chain-specific fields to `Spec`:
   ```zig
   pub const Spec = struct {
       // ... existing fields ...

       // L2-specific (optional)
       l1_fee_overhead: ?u64 = null,  // Optimism L1 data fee
       fee_vault: ?Address = null,    // Optimism fee recipient
       // ... more chain-specific fields
   };
   ```

3. Define chain-specific precompiles and system contracts in `updateHandlers`

**Benefits:** No changes to core architecture, clean separation between mainnet and L2 logic.

### Precompiles per Fork

Precompile management is not yet integrated with the fork system. Future work:
- Add precompile registry to `Spec`
- Allow forks to add/remove precompiles
- Support chain-specific precompiles (Optimism system contracts)

### Testing Implications

Fork-specific behavior should be tested:
- Integration tests that run the same bytecode on different forks
- Verify gas cost differences between forks
- Test feature flag enforcement (e.g., PUSH0 unavailable pre-Shanghai)
- Use `Spec.forFork()` to instantiate different fork configurations

Example:
```zig
test "PUSH0 unavailable before Shanghai" {
    const london = Spec.forFork(.LONDON);
    const shanghai = Spec.forFork(.SHANGHAI);

    try expect(!london.has_push0);
    try expect(shanghai.has_push0);

    // Test that PUSH0 is invalid in London
    var interp_london = try Interpreter.init(allocator, london, ...);
    const result = interp_london.run(&[_]u8{0x5F}); // PUSH0
    try expectError(error.InvalidOpcode, result);

    // Test that PUSH0 works in Shanghai
    var interp_shanghai = try Interpreter.init(allocator, shanghai, ...);
    // ... should succeed
}
```

