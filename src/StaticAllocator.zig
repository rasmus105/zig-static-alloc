// std imports
const std = @import("std");
const Allocator = std.mem.Allocator;

// ====================================================================================================
// Methods
// ====================================================================================================

const StaticAllocator = @This();

const BlockHeader = struct {
    next_block: ?*BlockHeader = null,
    prev_block: ?*BlockHeader = null,
};

const FlBitmap = std.meta.Int(.unsigned, FL_COUNT);
const SlBitmap = std.meta.Int(.unsigned, SL_COUNT);

// ====================================================================================================
// Methods
// ====================================================================================================

buffer_size: usize,
min_block_size: usize, // calculated once upon initialization
max_block_size: usize,
free_lists: [FL_COUNT][SL_COUNT]?*BlockHeader = @splat(@splat(null)),

// These bitmaps keep track of which free_lists indices are not null.
fl_bitmap: FlBitmap = 0,
sl_bitmaps: [FL_COUNT]SlBitmap = @splat(0),

// ====================================================================================================
// Methods - Math Helpers
// ====================================================================================================

inline fn lowerBound(size: usize) usize {
    return std.math.pow(usize, 2, std.math.floor(std.math.log2(size)));
}

inline fn upperBound(size: usize) usize {
    return std.math.pow(usize, 2, std.math.ceil(std.math.log2(size)));
}

// ====================================================================================================
// Methods - TFSC specific math helpers
// ====================================================================================================

// lowerBound = someTransform(buffer.len);
// lowerBound = 1024/(2^x)
// 2^x * lowerBound = 1024
// 2^x = 1024 * lowerBound
// x = log2(1024 * lowerBound)
// since 2^10 = 1024, then (note 2^y = x => y = log2(x))
// x = 10 * log2(lowerBound)
//
// someTransform:
// lower_bound = 2 ^ floor(log2(size))
fn sizeToFl(self: *const StaticAllocator, size: usize) usize {
    return std.math.log2(self.max_block_size) * std.math.log2(lowerBound(size));
}

// 356 => (lower bound) => 256
// 256 / SL_COUNT = 32
// (356 - 256) / 32 =
fn sizeToSl(_: *const StaticAllocator, size: usize) usize {
    const lower_bound = lowerBound(size);
    return @divTrunc((size - lower_bound), (lower_bound / SL_COUNT));
}

// ====================================================================================================
// Methods - "high level"
// ====================================================================================================

// ====================================================================================================
// Configuration Constants (consider moving these to build_config)
// ====================================================================================================

// number of second-level subdivisions.
pub const SL_COUNT = 8;
pub const FL_COUNT = 8;

// ====================================================================================================
// Public API
// ====================================================================================================

pub fn init(buffer: []u8) StaticAllocator {
    var self = StaticAllocator{
        .buffer_size = buffer.len,
        .min_block_size = lowerBound(buffer.len) / (std.math.pow(usize, 2, @intCast(FL_COUNT))),
        .max_block_size = upperBound(buffer.len + 1), // bounds are non-inclusive to the upper end, thus the +1
    };

    const first_block: *BlockHeader = &buffer[0];
    first_block.* = .{};

    const fl = self.sizeToFl(buffer.len);
    const sl = self.sizeToSl(buffer.len);

    // only 1 block
    self.free_lists[fl][sl] = first_block;
    self.fl_bitmap = 1 >> fl;
    self.sl_bitmaps[fl] = 1 >> sl;

    return self;
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
    return null;
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
    return false;
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
    return null;
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

// ====================================================================================================
// Tests
// ====================================================================================================

test {
    // _ = @import(@src().file[0 .. filename.len - 4] ++ ".test.zig");
    _ = @import("StaticAllocator.test.zig");
}
