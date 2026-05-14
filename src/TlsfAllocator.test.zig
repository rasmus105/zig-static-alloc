// TODO: fuzzy test allocator
const std = @import("std");
const TlsfAllocator = @import("TlsfAllocator.zig");

test "basic" {
    var buf: [4096]u8 = undefined;
    var tlsf = TlsfAllocator.init(&buf);
    const allocator = tlsf.allocator();

    const slice1 = try allocator.alloc(u8, 548);
    allocator.free(slice1);

    const slice2 = try allocator.alloc(u8, 512);
    allocator.free(slice2);
}
