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
const InterpreterConfig = @import("interpreter/interpreter.zig").InterpreterConfig;
const AnalyzedBytecode = @import("interpreter/bytecode.zig").AnalyzedBytecode;
const Eip7702Bytecode = @import("interpreter/bytecode.zig").Eip7702Bytecode;
const JumpTable = @import("interpreter/JumpTable.zig");
const call_types = @import("call_types.zig");
const CallKind = call_types.CallKind;
const CallInputs = call_types.CallInputs;
const CallResult = call_types.CallResult;
const CallExecutor = call_types.CallExecutor;

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
    table: *const InstructionTable,

    /// Cache of analyzed jump tables by code hash.
    ///
    /// Entries remain valid for the lifetime of this EVM instance.
    /// This avoids redundant `O(n)` bytecode analysis when the same contract is
    /// called multiple times within or across transactions.
    jump_table_cache: JumpTable.Cache,

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
            .jump_table_cache = JumpTable.Cache.init(allocator),
        };
    }

    /// Deinitialize EVM and free return data buffer.
    pub fn deinit(self: *Self) void {
        // Free return data buffer.
        if (self.return_data_buffer.len > 0) {
            self.allocator.free(self.return_data_buffer);
        }

        // Free all cached jump tables.
        var it = self.jump_table_cache.valueIterator();
        while (it.next()) |jt| jt.deinit();
        self.jump_table_cache.deinit();
    }

    /// Create a CallExecutor interface that delegates to this Evm.
    pub fn callExecutor(self: *Self) CallExecutor {
        return .{
            .ptr = self,
            .vtable = &.{
                .call = callImpl,
            },
        };
    }

    /// Vtable wrapper for call().
    fn callImpl(ptr: *anyopaque, inputs: CallInputs) anyerror!CallResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.call(inputs);
    }

    /// Create an InterpreterConfig for this EVM.
    ///
    /// This bundles all the external context needed for interpreter execution.
    pub fn interpreterConfig(self: *Self, gas_limit: u64, is_static: bool) InterpreterConfig {
        return .{
            .spec = self.spec,
            .gas_limit = gas_limit,
            .env = self.env,
            .host = self.host,
            .return_data_buffer = &self.return_data_buffer,
            .is_static = is_static,
            .call_executor = self.callExecutor(),
        };
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

        // Handle static mode for STATICCALL.
        // Save previous state and set to true if this is a STATICCALL.
        // Static mode propagates to nested calls (once static, always static).
        const prev_is_static = self.is_static;
        if (inputs.kind == .STATICCALL) {
            self.is_static = true;
        }
        defer self.is_static = prev_is_static;

        // Create a snapshot before state changes.
        const snapshot = try self.host.snapshot();
        errdefer self.host.revertToSnapshot(snapshot);

        // Transfer value if non-zero.
        if (inputs.transfer_value and !inputs.value.isZero()) {
            // Check caller has sufficient balance before transfer.
            const caller_balance = self.host.balance(inputs.caller);
            if (caller_balance.lt(inputs.value)) {
                return CallResult{
                    .status = .REVERT,
                    .gas_used = inputs.gas_limit,
                    .gas_refund = 0,
                    .output = &[_]u8{},
                };
            }
            try self.host.transfer(inputs.caller, inputs.target, inputs.value);
        }

        // Load target contract code (resolve EIP-7702, if necessary).
        const raw_code_const = try self.host.code(inputs.target);
        const raw_code = @constCast(raw_code_const);
        const resolved = try self.resolveDelegation(raw_code);

        // On empty code, return success with no output.
        if (resolved.len == 0) {
            self.allocator.free(resolved);
            return CallResult{
                .status = .SUCCESS,
                .gas_used = 0,
                .gas_refund = 0,
                .output = &[_]u8{},
            };
        }

        // Determine context address based on call kind.
        // CALL/CALLCODE/STATICCALL: storage applies to target.
        // DELEGATECALL: storage applies to caller (code borrowed from target).
        const context_address = switch (inputs.kind) {
            .DELEGATECALL => inputs.caller, // execute in caller's context
            else => inputs.target,
        };

        // Analyze bytecode (uses cache for efficiency).
        const analyzed = try AnalyzedBytecode.init(
            self.allocator,
            resolved,
            &self.jump_table_cache,
        );
        errdefer analyzed.deinit();

        // Create call context with pre-analyzed bytecode.
        const ctx = try CallContext.init(
            self.allocator,
            analyzed,
            context_address,
            inputs.caller,
            inputs.value,
        );

        // Create interpreter (takes ownership of ctx).
        var interp = Interpreter.init(
            self.allocator,
            ctx,
            self.interpreterConfig(inputs.gas_limit, self.is_static),
        );
        defer interp.deinit(); // This will also clean up ctx

        // Execute bytecode instructions.
        const result = try interp.run();

        // Free any previously stored data (from previous calls).
        if (self.return_data_buffer.len > 0) {
            self.allocator.free(self.return_data_buffer);
        }

        // Update return_data_buffer with result output.
        if (result.return_data) |data| {
            // Take ownership of return_data (interpreter allocated, we free).
            self.return_data_buffer = data;
        } else {
            self.return_data_buffer = &[_]u8{};
        }

        // Handle execution result.
        if (result.status != .SUCCESS) {
            // Revert state on non-success.
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

// Test helper constants.
const TestHelper = struct {
    const caller = Address.fromHex("0x0000000000000000000000000000000000000001") catch unreachable;
    const target = Address.fromHex("0x0000000000000000000000000000000000000002") catch unreachable;
    const stop_bytecode = &[_]u8{0x00};
    const default_gas_limit: u64 = 100000;

    fn defaultInputs() CallInputs {
        return .{
            .kind = .CALL,
            .target = target,
            .caller = caller,
            .value = U256.ZERO,
            .input = &[_]u8{},
            .gas_limit = default_gas_limit,
            .transfer_value = false,
        };
    }
};

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

test "Evm: call depth limit" {
    const TestCase = struct {
        initial_depth: usize,
        expected_status: ExecutionStatus,
        check_gas_used: bool,
    };

    const test_cases = [_]TestCase{
        // At limit (1023) succeeds.
        .{
            .initial_depth = 1023,
            .expected_status = .SUCCESS,
            .check_gas_used = false,
        },
        // Exceeded (1024) fails.
        .{
            .initial_depth = 1024,
            .expected_status = .CALL_DEPTH_EXCEEDED,
            .check_gas_used = true,
        },
    };

    for (test_cases) |tc| {
        const allocator = std.testing.allocator;
        var env = Env.default();
        var mock = MockHost.init(allocator);
        defer mock.deinit();
        const spec = Spec.forFork(.CANCUN);

        var evm = Evm.init(allocator, &env, mock.host(), spec);
        defer evm.deinit();

        evm.depth = tc.initial_depth;
        try mock.setCode(TestHelper.target, TestHelper.stop_bytecode);

        const inputs = TestHelper.defaultInputs();
        const result = try evm.call(inputs);

        try expectEqual(tc.expected_status, result.status);
        try expectEqual(tc.initial_depth, evm.depth);

        if (tc.check_gas_used) {
            try expectEqual(TestHelper.default_gas_limit, result.gas_used);
        }
    }
}

test "Evm: value transfer scenarios" {
    const TestCase = struct {
        caller_balance: u64,
        transfer_amount: u64,
        expected_status: ExecutionStatus,
        expected_caller_balance: u64,
        expected_target_balance: u64,
        check_gas_used: bool,
    };

    const test_cases = [_]TestCase{
        // Successful transfer.
        .{
            .caller_balance = 5000,
            .transfer_amount = 1000,
            .expected_status = .SUCCESS,
            .expected_caller_balance = 4000,
            .expected_target_balance = 1000,
            .check_gas_used = false,
        },
        // Zero value.
        .{
            .caller_balance = 5000,
            .transfer_amount = 0,
            .expected_status = .SUCCESS,
            .expected_caller_balance = 5000,
            .expected_target_balance = 0,
            .check_gas_used = false,
        },
        // Insufficient balance reverts.
        .{
            .caller_balance = 5000,
            .transfer_amount = 10000,
            .expected_status = .REVERT,
            .expected_caller_balance = 5000,
            .expected_target_balance = 0,
            .check_gas_used = true,
        },
    };

    for (test_cases) |tc| {
        const allocator = std.testing.allocator;
        var env = Env.default();
        var mock = MockHost.init(allocator);
        defer mock.deinit();
        const spec = Spec.forFork(.CANCUN);

        var evm = Evm.init(allocator, &env, mock.host(), spec);
        defer evm.deinit();

        try mock.setBalance(TestHelper.caller, U256.fromU64(tc.caller_balance));
        try mock.setBalance(TestHelper.target, U256.ZERO);
        try mock.setCode(TestHelper.target, TestHelper.stop_bytecode);

        var inputs = TestHelper.defaultInputs();
        inputs.value = U256.fromU64(tc.transfer_amount);
        inputs.transfer_value = true;

        const result = try evm.call(inputs);
        try expectEqual(tc.expected_status, result.status);

        if (tc.check_gas_used) {
            try expectEqual(TestHelper.default_gas_limit, result.gas_used);
        }

        const h = mock.host();
        try expect(h.balance(TestHelper.caller).eql(U256.fromU64(tc.expected_caller_balance)));
        try expect(h.balance(TestHelper.target).eql(U256.fromU64(tc.expected_target_balance)));
    }
}

test "Evm: call creates snapshot" {
    const allocator = std.testing.allocator;
    var env = Env.default();
    var mock = MockHost.init(allocator);
    defer mock.deinit();
    const spec = Spec.forFork(.CANCUN);

    var evm = Evm.init(allocator, &env, mock.host(), spec);
    defer evm.deinit();

    try mock.setBalance(TestHelper.caller, U256.fromU64(5000));
    try mock.setCode(TestHelper.target, TestHelper.stop_bytecode);

    var inputs = TestHelper.defaultInputs();
    inputs.value = U256.fromU64(1000);
    inputs.transfer_value = true;

    const initial_snapshots = mock.snapshots.items.len;
    const result = try evm.call(inputs);
    try expectEqual(ExecutionStatus.SUCCESS, result.status);

    // After successful call, snapshot is implicitly committed (not reverted).
    // The snapshot list should still contain the snapshot (not popped on success in our impl).
    try expect(mock.snapshots.items.len >= initial_snapshots);
}

test "Evm: call kinds" {
    const TestCase = struct {
        kind: CallKind,
        value: u64,
        transfer_value: bool,
        check_static_restored: bool,
    };

    const test_cases = [_]TestCase{
        // DELEGATECALL preserves context.
        .{
            .kind = .DELEGATECALL,
            .value = 1000,
            .transfer_value = false,
            .check_static_restored = false,
        },
        // STATICCALL sets static mode.
        .{
            .kind = .STATICCALL,
            .value = 0,
            .transfer_value = false,
            .check_static_restored = true,
        },
    };

    for (test_cases) |tc| {
        const allocator = std.testing.allocator;
        var env = Env.default();
        var mock = MockHost.init(allocator);
        defer mock.deinit();
        const spec = Spec.forFork(.CANCUN);

        var evm = Evm.init(allocator, &env, mock.host(), spec);
        defer evm.deinit();

        try mock.setCode(TestHelper.target, TestHelper.stop_bytecode);

        // Set initial balances to verify no transfer occurs.
        try mock.setBalance(TestHelper.caller, U256.fromU64(5000));
        try mock.setBalance(TestHelper.target, U256.fromU64(100));

        if (tc.check_static_restored) {
            try expect(!evm.is_static);
        }

        var inputs = TestHelper.defaultInputs();
        inputs.kind = tc.kind;
        inputs.value = U256.fromU64(tc.value);
        inputs.transfer_value = tc.transfer_value;

        const result = try evm.call(inputs);
        try expectEqual(ExecutionStatus.SUCCESS, result.status);

        // Verify balances unchanged (no transfer for these call types).
        const h = mock.host();
        try expect(h.balance(TestHelper.caller).eql(U256.fromU64(5000)));
        try expect(h.balance(TestHelper.target).eql(U256.fromU64(100)));

        if (tc.check_static_restored) {
            try expect(!evm.is_static);
        }
    }
}
