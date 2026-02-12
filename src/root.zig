const std = @import("std");

test {
    _ = @import("StaticAllocator.zig");

    try std.testing.expect(true == !false);
}
