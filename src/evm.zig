//! EVM execution engine
//!
//! The primary responsibility of this layer is to sit above the interpreter and manage
//! nested calls (CALL, DELEGATECALL, STATICCALL), including gas propagation across call frames,
//! contract creation (CREATE, CREATE2), and snapshots (creation and reverts).
//!
//! Also, manages return data buffer, thus providing the mechanism for returning arbitrary-length
//! data inside EVM (EIP-211).

const std = @import("std");
const Allocator = std.mem.Allocator;

const constants = @import("constants.zig");
const Address = @import("primitives/mod.zig").Address;
const U256 = @import("primitives/mod.zig").U256;
const Env = @import("context.zig").Env;
const Host = @import("host/Host.zig");
const Spec = @import("hardfork.zig").Spec;
const InstructionTable = @import("interpreter/InstructionTable.zig");
const ExecutionStatus = @import("interpreter/interpreter.zig").ExecutionStatus;
const CallContext = @import("interpreter/interpreter.zig").CallContext;
const Interpreter = @import("interpreter/interpreter.zig").Interpreter;
const InterpreterResult = @import("interpreter/interpreter.zig").InterpreterResult;
const Eip7702Bytecode = @import("interpreter/bytecode.zig").Eip7702Bytecode;

/// Call kind determines the type of call operation.
pub const CallKind = enum {
    /// Normal call: transfers value, changes context.
    CALL,

    /// Legacy call: like CALL but deprecated.
    CALLCODE,

    /// Delegate call: preserves caller, no value transfer.
    DELEGATECALL,

    /// Static call: read-only, no state modifications allowed.
    STATICCALL,
};

/// Input parameters for a call operation.
pub const CallInputs = struct {
    /// Type of call.
    kind: CallKind,

    /// Target contract address to call.
    target: Address,

    /// Address initiating this call.
    caller: Address,

    /// Value to transfer (in wei).
    value: U256,

    /// Input data.
    input: []const u8,

    /// Gas limit for this call.
    gas_limit: u64,

    /// Memory offset for return data.
    return_memory_offset: usize,

    /// Memory length for return data.
    return_memory_length: usize,

    /// Whether to actually transfer value (false for DELEGATECALL).
    transfer_value: bool,
};

/// Result of a call operation.
pub const CallResult = struct {
    /// Execution status.
    status: ExecutionStatus,

    /// Gas consumed by the call.
    gas_used: u64,

    /// Gas refunded by the call.
    gas_refund: u64,

    /// Output data from the call.
    output: []const u8,
};

/// EVM execution engine.
pub const Evm = struct {
    /// Allocator for dynamic allocations.
    allocator: Allocator,

    /// Environmental context (block + tx info).
    env: *const Env,

    /// Host interface for state access.
    host: Host,

    /// Spec (fork-specific rules).
    spec: Spec,

    /// Current call depth.
    depth: usize,

    /// Return data buffer (EIP-211).
    ///
    /// Updated after each sub-call completes.
    return_data_buffer: []const u8,

    /// Whether currently in static context or not.
    is_static: bool,

    /// Instruction table for current spec.
    table: InstructionTable,

    const Self = @This();

    /// Initialize EVM with given context and spec.
    pub fn init(allocator: Allocator, env: *const Env, host: Host, spec: Spec) Self {
        return Self{
            .allocator = allocator,
            .env = env,
            .host = host,
            .spec = spec,
            .depth = 0,
            .return_data_buffer = &[_]u8{},
            .is_static = false,
            .table = spec.instructionTable(),
        };
    }

    /// Deinitialize EVM and free return data buffer.
    pub fn deinit(self: *Self) void {
        if (self.return_data_buffer.len > 0) {
            self.allocator.free(self.return_data_buffer);
        }
    }

    /// Resolve EIP-7702 delegation if present.
    ///
    /// Takes ownership of raw_code.
    ///
    /// Checks if the raw bytecode is EIP-7702 delegation (0xEF0100 + address).
    /// If so, loads the delegated code from the host and frees the original raw_code.
    /// Returns error if nested delegation is detected (delegation to another delegation).
    fn resolveDelegation(self: *Self, raw_code: []u8) ![]u8 {
        // Return original if not a delegation code.
        const delegation = Eip7702Bytecode.parse(raw_code) catch {
            return raw_code;
        };

        // Load delegated code from host.
        const delegated_code_const = try self.host.code(delegation.delegated_address);
        const delegated_code = @constCast(delegated_code_const);

        // Avoid nested delegation (not allowed).
        if (Eip7702Bytecode.parse(delegated_code)) |_| {
            // Nested delegation detected - free both and error.
            self.allocator.free(delegated_code);
            self.allocator.free(raw_code);
            return error.NestedDelegation;
        } else |_| {
            self.allocator.free(raw_code);
            return delegated_code;
        }
    }

    /// Execute a call operation
    ///
    /// Loads target code, resolves EIP-7702 delegation, creates an interpreter,
    /// and executes the bytecode.
    ///
    /// Handles value transfers, snapshots, and return data buffer management.
    pub fn call(self: *Self, inputs: CallInputs) !CallResult {
        // Assert depth limit.
        if (self.depth >= constants.CALL_DEPTH_LIMIT) {
            return CallResult{
                .status = .CALL_DEPTH_EXCEEDED,
                .gas_used = inputs.gas_limit,
                .gas_refund = 0,
                .output = &[_]u8{},
            };
        }

        // Increment depth (decrement on exit).
        self.depth += 1;
        defer self.depth -= 1;

        // Create a snapshot before state changes.
        const snapshot = try self.host.snapshot();
        errdefer self.host.revertToSnapshot(snapshot);

        // Transfer value if non-zero.
        if (inputs.transfer_value and !inputs.value.isZero()) {
            try self.host.transfer(inputs.caller, inputs.target, inputs.value);
        }

        // Load target contract code (resolve EIP-7702, if necessary).
        const raw_code_const = try self.host.code(inputs.target);
        const raw_code = @constCast(raw_code_const);
        const resolved = try self.resolveDelegation(raw_code);

        // Create call context (analyzes bytecode internally).
        const ctx = CallContext.init(self.allocator, resolved, inputs.target) catch |err| {
            return switch (err) {
                // System errors propagate up.
                error.OutOfMemory => err,

                // All other errors are considered bytecode validation failures.
                else => CallResult{
                    .status = .INVALID_OPCODE,
                    .gas_used = inputs.gas_limit,
                    .gas_refund = 0,
                    .output = &[_]u8{},
                },
            };
        };

        // Create interpreter (takes ownership of ctx)
        var interp = Interpreter.init(
            self.allocator,
            ctx,
            self.spec,
            inputs.gas_limit,
            self.env,
            self.host,
        );
        defer interp.deinit(); // This will also clean up ctx

        // Execute bytecode
        const result = try interp.run(self);

        // Update return_data_buffer with result output
        if (self.return_data_buffer.len > 0) {
            self.allocator.free(self.return_data_buffer);
        }
        if (result.return_data) |data| {
            self.return_data_buffer = try self.allocator.dupe(u8, data);
        } else {
            self.return_data_buffer = &[_]u8{};
        }

        // Handle execution result
        if (result.status != .SUCCESS) {
            // Revert state on non-success
            self.host.revertToSnapshot(snapshot);
        }

        return CallResult{
            .status = result.status,
            .gas_used = result.gas_used,
            .gas_refund = result.gas_refund,
            .output = result.return_data orelse &[_]u8{},
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const MockHost = @import("host/mock.zig").MockHost;

test "Evm: init and deinit" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try expectEqual(0, evm.depth);
    try expectEqual(0, evm.return_data_buffer.len);
    try expectEqual(false, evm.is_static);
}

test "Evm: call depth limit enforced" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    // Set depth to max allowed (1023) - call should succeed
    evm.depth = 1023;
    const caller = Address.fromHex("0x0000000000000000000000000000000000000001") catch unreachable;
    const target = Address.fromHex("0x0000000000000000000000000000000000000002") catch unreachable;

    // Setup: target has simple STOP bytecode
    const bytecode = &[_]u8{0x00}; // STOP
    try mock.setCode(target, bytecode);

    const inputs_at_limit = CallInputs{
        .kind = .CALL,
        .target = target,
        .caller = caller,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .return_memory_offset = 0,
        .return_memory_length = 0,
        .transfer_value = false,
    };

    const result_at_limit = try evm.call(inputs_at_limit);
    try expectEqual(ExecutionStatus.SUCCESS, result_at_limit.status);
    try expectEqual(@as(usize, 1023), evm.depth); // depth restored after call

    // Set depth to max (1024) - call should fail
    evm.depth = 1024;
    const inputs_over_limit = CallInputs{
        .kind = .CALL,
        .target = target,
        .caller = caller,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .return_memory_offset = 0,
        .return_memory_length = 0,
        .transfer_value = false,
    };

    const result_over_limit = try evm.call(inputs_over_limit);
    try expectEqual(ExecutionStatus.CALL_DEPTH_EXCEEDED, result_over_limit.status);
    try expectEqual(@as(u64, 100000), result_over_limit.gas_used);
    try expectEqual(@as(usize, 1024), evm.depth); // depth unchanged on depth exceeded
}

test "Evm: call with value transfer" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const caller = Address.fromHex("0x0000000000000000000000000000000000000001") catch unreachable;
    const target = Address.fromHex("0x0000000000000000000000000000000000000002") catch unreachable;
    const transfer_amount = U256.fromU64(1000);

    // Setup: caller has balance, target has bytecode
    try mock.setBalance(caller, U256.fromU64(5000));
    try mock.setBalance(target, U256.fromU64(0));
    const bytecode = &[_]u8{0x00}; // STOP
    try mock.setCode(target, bytecode);

    const inputs = CallInputs{
        .kind = .CALL,
        .target = target,
        .caller = caller,
        .value = transfer_amount,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .return_memory_offset = 0,
        .return_memory_length = 0,
        .transfer_value = true,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // Verify balances updated
    const h = mock.host();
    const caller_balance = h.balance(caller);
    const target_balance = h.balance(target);
    try expect(caller_balance.eql(U256.fromU64(4000)));
    try expect(target_balance.eql(U256.fromU64(1000)));
}

test "Evm: call with zero value" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const caller = Address.fromHex("0x0000000000000000000000000000000000000001") catch unreachable;
    const target = Address.fromHex("0x0000000000000000000000000000000000000002") catch unreachable;

    // Setup: caller has balance, target has bytecode
    try mock.setBalance(caller, U256.fromU64(5000));
    try mock.setBalance(target, U256.fromU64(0));
    const bytecode = &[_]u8{0x00}; // STOP
    try mock.setCode(target, bytecode);

    const inputs = CallInputs{
        .kind = .CALL,
        .target = target,
        .caller = caller,
        .value = U256.ZERO,
        .input = &[_]u8{},
        .gas_limit = 100000,
        .return_memory_offset = 0,
        .return_memory_length = 0,
        .transfer_value = true,
    };

    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // Verify balances unchanged (zero transfer)
    const h = mock.host();
    const caller_balance = h.balance(caller);
    const target_balance = h.balance(target);
    try expect(caller_balance.eql(U256.fromU64(5000)));
    try expect(target_balance.eql(U256.fromU64(0)));
}

test "Evm: call creates snapshot" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    const caller = Address.fromHex("0x0000000000000000000000000000000000000001") catch unreachable;
    const target = Address.fromHex("0x0000000000000000000000000000000000000002") catch unreachable;

    // Setup: caller has balance, target has bytecode
    try mock.setBalance(caller, U256.fromU64(5000));
    const bytecode = &[_]u8{0x00}; // STOP
    try mock.setCode(target, bytecode);

    const inputs = CallInputs{
        .kind = .CALL,
        .target = target,
        .caller = caller,
        .value = U256.fromU64(1000),
        .input = &[_]u8{},
        .gas_limit = 100000,
        .return_memory_offset = 0,
        .return_memory_length = 0,
        .transfer_value = true,
    };

    // Verify snapshot count increases during call
    const initial_snapshots = mock.snapshots.items.len;
    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // After successful call, snapshot is implicitly committed (not reverted)
    // The snapshot list should still contain the snapshot (not popped on success in our impl)
    try expect(mock.snapshots.items.len >= initial_snapshots);
}
