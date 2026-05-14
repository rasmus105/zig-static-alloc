const std = @import("std");

test {
    _ = @import("TlsfAllocator.zig");
    _ = @import("queue.zig");

    try std.testing.expect(true == !false);
}
