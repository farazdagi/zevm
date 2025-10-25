const std = @import("std");
const zevm = @import("zevm");

pub fn main() !void {
    std.debug.print("Vrr, vrr, computing: {}\n", .{zevm.add(30, 12)});
}
