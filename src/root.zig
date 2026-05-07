const std = @import("std");

test {
    _ = @import("StaticAllocator.zig");
    _ = @import("queue.zig");

    try std.testing.expect(true == !false);
}
