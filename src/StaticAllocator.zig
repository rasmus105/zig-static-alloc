const std = @import("std");
const Allocator = std.mem.Allocator;

const StaticAllocator = @This();

pub fn init(buffer: []u8) StaticAllocator {
    _ = buffer;
}

pub fn allocator(self: *StaticAllocator) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

pub fn alloc(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    _ = self;
    _ = n;
    _ = alignment;
    _ = ra;
}

pub fn resize(
    ctx: *anyopaque,
    buf: []u8,
    alignment: std.mem.Alignment,
    new_size: usize,
    return_address: usize,
) bool {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    _ = self;
    _ = buf;
    _ = alignment;
    _ = new_size;
    _ = return_address;
}

pub fn remap(
    ctx: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    return_address: usize,
) ?[*]u8 {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    _ = self;
    _ = memory;
    _ = alignment;
    _ = new_len;
    _ = return_address;
}

pub fn free(
    ctx: *anyopaque,
    buf: []u8,
    alignment: std.mem.Alignment,
    return_address: usize,
) void {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    _ = self;
    _ = buf;
    _ = alignment;
    _ = return_address;
}
