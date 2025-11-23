//! Logging instruction handlers.

const std = @import("std");
const U256 = @import("../../primitives/big.zig").U256;
const B256 = @import("../../primitives/bytes.zig").B256;
const Interpreter = @import("../interpreter.zig").Interpreter;
const Log = @import("../../Log.zig");

/// Generic LOG handler for LOG0-LOG4.
///
/// Stack: [offset, size, topic1, topic2, ..., topicN]
/// EIP-214: Static calls cannot emit logs.
pub fn makeOpLogFn(comptime topic_count: u3) *const fn (*Interpreter) Interpreter.Error!void {
    return struct {
        fn handler(interp: *Interpreter) Interpreter.Error!void {
            // EIP-214: Static calls cannot emit logs
            if (interp.is_static) {
                return error.StateWriteInStaticCall;
            }

            // Pop offset and size from stack
            const offset_u256 = try interp.ctx.stack.pop();
            const size_u256 = try interp.ctx.stack.pop();

            const offset = offset_u256.toUsize() orelse return error.InvalidOffset;
            const size = size_u256.toUsize() orelse return error.InvalidOffset;

            // Pop topics from stack (topic_count is comptime, so this loop unrolls)
            var topics: [4]B256 = undefined;
            comptime var i: u3 = 0;
            inline while (i < topic_count) : (i += 1) {
                const topic_u256 = try interp.ctx.stack.pop();
                topics[i] = B256.init(topic_u256.toBeBytes());
            }

            // Get data from memory (zero-copy - just borrow the slice)
            const data = try interp.ctx.memory.getSlice(offset, size);

            // Create log entry
            const log_entry = Log.init(
                interp.ctx.contract.address,
                topics[0..topic_count],
                data,
            );

            // Emit log via host
            interp.host.log(log_entry);
        }
    }.handler;
}
