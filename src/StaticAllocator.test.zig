const std = @import("std");
const StaticAllocator = @import("StaticAllocator.zig");

test "basic" {
    var buf: [4096]u8 = undefined;
    var x = StaticAllocator.init(&buf);
    const allocator = x.allocator();

    const slice1 = try allocator.alloc(u8, 2048);
    const slice2 = try allocator.alloc(u8, 1024);
    const slice3 = try allocator.alloc(u8, 512);
    const slice4 = try allocator.alloc(u8, 256);
    const slice5 = try allocator.alloc(u8, 128);
    const slice6 = try allocator.alloc(u8, 128);

    allocator.free(slice1);
    allocator.free(slice2);
    allocator.free(slice3);
    allocator.free(slice4);
    allocator.free(slice5);
    allocator.free(slice6);
}
