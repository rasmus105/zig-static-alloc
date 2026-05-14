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

test "out of order frees" {
    var buf: [4096]u8 = undefined;
    var tlsf = TlsfAllocator.init(&buf);
    const allocator = tlsf.allocator();

    const slice1 = try allocator.alloc(u8, 548);
    const slice2 = try allocator.alloc(u8, 512);
    const slice3 = try allocator.alloc(u8, 912);
    const slice4 = try allocator.alloc(u8, 112);

    allocator.free(slice3);
    allocator.free(slice4);
    allocator.free(slice2);
    allocator.free(slice1);
}

test "ton of allocations" {
    var buf: [10 * 1024 * 1024]u8 = undefined;
    var tlsf = TlsfAllocator.init(&buf);
    const allocator = tlsf.allocator();
    const iterations = 500;

    var mem_buf: [iterations][]u8 = undefined;
    var slice_mem_array = std.ArrayList([]u8).initBuffer(&mem_buf);

    for (0..iterations) |i| {
        try slice_mem_array.appendBounded(try allocator.alloc(u8, i * 17));
    }

    for (0..iterations) |_| {
        const mem = slice_mem_array.pop() orelse return error.EmptyList;
        allocator.free(mem);
    }
}
