//! TODO:
//! - [ ] Cache certain often-used values for optimization

// std imports
const std = @import("std");
const Allocator = std.mem.Allocator;

// ====================================================================================================
// Methods
// ====================================================================================================

const StaticAllocator = @This();

const BlockHeader = struct {
    prev_phys_block: ?*BlockHeader = null,
    next_block: ?*BlockHeader = null,
    prev_block: ?*BlockHeader = null,
    size: usize,

    pub fn init(address: usize, size: usize, prev_block: ?*BlockHeader) *BlockHeader {
        const ptr: *BlockHeader = @ptrFromInt(address);
        ptr.* = BlockHeader{
            .prev_phys_block = null,
            .next_block = null,
            .prev_block = prev_block,
            .size = size,
        };
        return ptr;
    }

    pub fn remove(self: *BlockHeader) void {
        if (self.prev_block) |prev| {
            prev.next_block = self.next_block;
        } else if (self.next_block) |next| {
            next.prev_block = self.prev_block;
        }

        self.next_block = null;
        self.prev_block = null;
    }

    pub fn from(address: usize) *BlockHeader {
        return @ptrFromInt(address);
    }

    inline fn addr(self: *const BlockHeader) usize {
        return @intFromPtr(self);
    }
};

const FlBitmap = std.meta.Int(.unsigned, FL_COUNT);
const SlBitmap = std.meta.Int(.unsigned, SL_COUNT);

// note: These are zero-indexed. FL_COUNT may be 8, while Fl goes from 0-7.
const Fl = std.math.Log2Int(std.meta.Int(.unsigned, FL_COUNT));
const Sl = std.math.Log2Int(std.meta.Int(.unsigned, SL_COUNT));

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

/// user-provided buffer for allocations
buffer: []u8,

// ====================================================================================================
// Methods - Math Helpers
// ====================================================================================================

/// Round `size` down to the closest `2^x` value
inline fn lowerBound(size: usize) usize {
    std.debug.assert(size > 0);

    const shift: std.math.Log2Int(usize) =
        @intCast(@bitSizeOf(usize) - 1 - @clz(size));

    return @as(usize, 1) << shift;
}

test lowerBound {
    try std.testing.expectEqual(1024, lowerBound(1221));
    try std.testing.expectEqual(32, lowerBound(33));
    try std.testing.expectEqual(1, lowerBound(1)); // 2^0
    try std.testing.expectEqual(2, lowerBound(3)); // 2^0
}

/// Round `size` up to the closest `2^x` value
inline fn upperBound(size: usize) usize {
    std.debug.assert(size > 0);

    const lower = lowerBound(size);
    if (lower == size) return size;

    return lower << 1;
}

test upperBound {
    try std.testing.expectEqual(2048, upperBound(1221));
    try std.testing.expectEqual(64, upperBound(33));
    try std.testing.expectEqual(1, upperBound(1)); // 2^0
    try std.testing.expectEqual(4, upperBound(3)); // 2^0
}

// ====================================================================================================
// Methods - TFSC specific math helpers
// ====================================================================================================

// Fl = log2(max_block_size) * log2(lowerBoundOf(size))
// Sl = (size-lowerBoundOf(size)) / (lowerBoundOf(size) / SL_COUNT)
// where:
//  lowerBoundOf(size) = 2^(floor(log2(size)))
/// Find closest matching bin
fn sizeToLevels(self: *const StaticAllocator, size: usize) struct { Fl, Sl } {
    const lower_bound = lowerBound(size);

    std.debug.print("size = {d}\n", .{size});

    // - 1 since they are zero-indexed.
    const fl: Fl = @intCast(std.math.log2(lower_bound) - std.math.log2(self.min_block_size) - 1);
    const sl: Sl = @intCast(@divTrunc((size - lower_bound), (lower_bound / SL_COUNT)));
    return .{ fl, sl };
}

// size =
// (have to reverse above equations)
fn flToSize(self: *const StaticAllocator, fl: Fl) usize {
    return std.math.pow(usize, 2, std.math.log2(self.min_block_size) + fl);
}

fn sizeFromLevels(self: *const StaticAllocator, sl: Sl, fl: Fl) usize {
    const lower_bound_size = self.flToSize(fl);
    return (lower_bound_size / SL_COUNT) * sl + lower_bound_size;
}

// ====================================================================================================
// Methods - "high level"
// ====================================================================================================

/// finds Fl/Sl of the buffer with the closest size to allocate `n` bytes
fn findFreeBlock(self: *const StaticAllocator, n: usize) ?struct { Fl, Sl } {
    const min_fl, const min_sl = self.sizeToLevels(n);

    const shifted_fl_bitmap = self.fl_bitmap << min_fl;

    if (shifted_fl_bitmap == 0) return null; // no free room
    const leading_zeroes_fl = @clz(shifted_fl_bitmap);
    const fl: Fl = @intCast(min_fl + leading_zeroes_fl);

    const shifted_sl_bitmap = self.sl_bitmaps[fl] << min_sl;
    if (shifted_sl_bitmap == 0) {
        // have to go to next fl level - no sl level big enough here
        const next_shifted_fl_bitmap = self.fl_bitmap << fl;
        if (next_shifted_fl_bitmap == 0) return null;
        const next_fl = @clz(next_shifted_fl_bitmap);
        const next_shifted_sl_bitmap = self.sl_bitmaps[next_fl];
        std.debug.assert(next_shifted_sl_bitmap != 0);

        const leading_zeroes_sl = @clz(shifted_sl_bitmap);
        const sl: Sl = @intCast(min_sl + leading_zeroes_sl);

        return .{ @as(Fl, @intCast(fl)), @as(Sl, @intCast(sl)) };
    }
    const leading_zeroes_sl = @clz(shifted_sl_bitmap);
    const sl: Sl = @intCast(min_sl + leading_zeroes_sl);

    return .{ fl, sl };
}

fn bitmapAdd(self: *StaticAllocator, fl: Fl, sl: Sl) void {
    self.fl_bitmap |= @as(FlBitmap, 1) << fl;
    self.sl_bitmaps[fl] |= @as(SlBitmap, 1) << sl;
}

fn bitmapRemove(self: *StaticAllocator, fl: Fl, sl: Sl) void {
    self.sl_bitmaps[fl] &= ~(@as(SlBitmap, 1) << sl);
    if (self.sl_bitmaps[fl] == 0) { // only clear once entire second level becomes empty.
        self.fl_bitmap &= ~(@as(FlBitmap, 1) << fl);
    }
}

fn removeFreeBlock(self: *StaticAllocator, block: *BlockHeader, fl: Fl, sl: Sl) void {
    std.debug.assert(self.free_lists[fl][sl] == null);

    block.remove(); // remove references
    self.free_lists[fl][sl] = null;
    self.bitmapRemove(fl, sl);
}

fn insertFreeBlock(self: *StaticAllocator, block: *BlockHeader) void {
    const fl, const sl = self.sizeToLevels(block.size);
    if (self.free_lists[fl][sl]) |prev_block| {
        block.prev_block = prev_block;
        prev_block.next_block = block;
    } else {
        self.free_lists[fl][sl] = block;
        self.bitmapAdd(fl, sl);
    }
}

fn mergeBlocks(self: *StaticAllocator, free_block: *BlockHeader, allocated_block: *BlockHeader) void {
    std.debug.assert(free_block.size > 0);
    std.debug.assert(allocated_block.size > 0);
    std.debug.assert(free_block.addr() < allocated_block.addr());

    const fl, const sl = self.sizeToLevels(free_block.size);
    self.removeFreeBlock(free_block, fl, sl);

    const total_size = free_block.size + allocated_block.size;
    const merged_block = BlockHeader.init(free_block.addr(), total_size, null);
    self.insertFreeBlock(merged_block);
}

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
        .buffer = buffer,
        .min_block_size = lowerBound(buffer.len) / (std.math.pow(usize, 2, @intCast(FL_COUNT))),
        .max_block_size = upperBound(buffer.len + 1), // bounds are non-inclusive to the upper end, thus the +1
    };

    const first_block = BlockHeader.init(@intFromPtr(buffer.ptr), buffer.len, null);

    const fl, const sl = self.sizeToLevels(buffer.len);

    // only 1 block
    self.free_lists[fl][sl] = first_block;
    self.fl_bitmap = @as(FlBitmap, 1) >> fl;
    self.sl_bitmaps[fl] = @as(SlBitmap, 1) >> sl;

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

pub fn alloc(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
    _ = return_address;
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));

    const worst_case_n = @sizeOf(BlockHeader) + n + @max(alignment.toByteUnits() - 1, @sizeOf(BlockHeader));
    const fl, const sl = self.findFreeBlock(worst_case_n) orelse return null;
    const block = self.free_lists[fl][sl].?; // if this fails bitmap has lied to us
    self.removeFreeBlock(block, fl, sl); // remove references to this block
    const aligned_addr = std.mem.alignBackward(usize, block.addr() + block.size - n, alignment.toByteUnits());

    const padding = aligned_addr - block.addr() - @sizeOf(BlockHeader);
    std.debug.assert(padding > @sizeOf(BlockHeader));

    // initialize free block
    const new_free_block = BlockHeader.init(block.addr(), padding, block.prev_phys_block);
    self.insertFreeBlock(new_free_block);

    // initialize allocated block
    _ = BlockHeader.init(aligned_addr - @sizeOf(BlockHeader), @sizeOf(BlockHeader) + n, new_free_block);
    return @ptrFromInt(aligned_addr);
}

pub fn resize(
    ctx: *anyopaque,
    buf: []u8,
    alignment: std.mem.Alignment,
    new_size: usize,
    return_address: usize,
) bool {
    _ = return_address; // not used - though may be useful for future debugging
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    _ = self;
    _ = buf;
    _ = alignment;
    _ = new_size;
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
    _ = alignment;
    _ = return_address;
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));

    const block: *BlockHeader = @ptrCast(@alignCast(buf.ptr - @sizeOf(BlockHeader)));
    if (block.prev_phys_block) |prev| {
        self.mergeBlocks(prev, block);
    } else {
        self.insertFreeBlock(block);
    }
}

// ====================================================================================================
// Tests
// ====================================================================================================

test {
    // _ = @import(@src().file[0 .. filename.len - 4] ++ ".test.zig");
    _ = @import("TlsfAllocator.test.zig");
}
