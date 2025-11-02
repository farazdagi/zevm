const std = @import("std");
const zevm = @import("zevm");

pub fn main() !void {
    std.debug.print("Vrr, vrr, computing: {}\n", .{zevm.add(30, 12)});
}

test "add_two_numbers" {
    try std.testing.expect(zevm.add(2, 2) == 4);
    return error.SkipZigTest;
}
