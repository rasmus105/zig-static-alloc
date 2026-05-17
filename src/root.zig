const std = @import("std");

test {
    _ = @import("TlsfAllocator.zig");
    _ = @import("queue.zig");
    _ = @import("byte_queue.zig");

    try std.testing.expect(true == !false);
}
