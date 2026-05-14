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

    pub fn init(addr: usize, size: usize, prev_block: ?*BlockHeader) *BlockHeader {
        const ptr: *BlockHeader = @ptrFromInt(addr);
        ptr.* = BlockHeader{
            .prev_phys_block = null;
            .next_block = null,
            .prev_block = prev_block,
            .siez = size,
        };
        return ptr;
    }

    inline fn addr(self: *const BlockHeader) usize {
        @intFromPtr(self);
    }
};

const FlBitmap = std.meta.Int(.unsigned, FL_COUNT);
const SlBitmap = std.meta.Int(.unsigned, SL_COUNT);

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

inline fn lowerBound(size: usize) usize {
    return std.math.pow(usize, 2, std.math.floor(std.math.log2(size)));
}

inline fn upperBound(size: usize) usize {
    return std.math.pow(usize, 2, std.math.ceil(std.math.log2(size)));
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

    const fl = std.math.log2(lowerBound(size)) - std.math.log2(self.min_block_size);
    const sl = @divTrunc((size - lower_bound), (lower_bound / SL_COUNT));
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
fn findFreeLevels(self: *const StaticAllocator, n: usize) ?struct { Fl, Sl } {
    const min_fl, const min_sl = self.sizeToLevels(n);

    const shifted_fl_bitmap = self.fl_bitmap << min_fl;

    if (shifted_fl_bitmap == 0) return null; // no free room
    const leading_zeroes_fl = @clz(shifted_fl_bitmap);
    const fl = min_fl + leading_zeroes_fl;

    const shifted_sl_bitmap = self.sl_bitmaps[fl] << min_sl;
    if (shifted_sl_bitmap == 0) {
        // have to go to next fl level - no sl level big enough here
        const next_shifted_fl_bitmap = self.fl_bitmap << fl;
        if (next_shifted_fl_bitmap == 0) return null;
        const next_fl = @clz(next_shifted_fl_bitmap);
        const next_shifted_sl_bitmap = self.sl_bitmaps[next_fl];
        std.debug.assert(next_shifted_sl_bitmap != 0);

        const leading_zeroes_sl = @clz(shifted_sl_bitmap);
        const sl = min_sl + leading_zeroes_sl;

        std.debug.assert(fl <= std.math.maxInt(Fl));
        std.debug.assert(sl <= std.math.maxInt(Sl));
        return .{ @as(Fl, @intCast(fl)), @as(Sl, @intCast(sl)) };
    }
    const leading_zeroes_sl = @clz(shifted_sl_bitmap);
    const sl = min_sl + leading_zeroes_sl;

    std.debug.assert(fl <= std.math.maxInt(Fl));
    std.debug.assert(sl <= std.math.maxInt(Sl));

    return .{ @as(Fl, @intCast(fl)), @as(Sl, @intCast(sl)) };
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

    const first_block: *BlockHeader = &buffer[0];
    first_block.* = .{};

    const fl, const sl = self.sizeToLevels(buffer.len);

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

fn bitmapAdd(self: *StaticAllocator, fl: Fl, sl: Sl) void {
    self.fl_bitmap |= 1 << fl;
    self.sl_bitmaps[fl] |= 1 << sl;
}

fn bitmapRemove(self: *StaticAllocator, fl: Fl, sl: Sl) void {
    self.sl_bitmaps[fl] &= ~(1 << sl);
    if (self.sl_bitmaps[fl] == 0) { // only clear once entire second level becomes empty.
        self.fl_bitmap &= ~(1 << fl);
    }
}

/// Insert some bytes of allocated memory in list
fn insertInList(self: *StaticAllocator, addr: usize, n: usize) void {
    std.debug.assert(n >= @sizeOf(BlockHeader));
    const fl, const sl = self.sizeToLevels(n);
    if (self.free_lists[fl][sl]) |list| {
        self.free_lists[fl][sl] = BlockHeader.init(addr, list);
    } else {
        self.free_lists[fl][sl] = BlockHeader.init(addr, null);
        self.bitmapAdd(fl, sl);
    }
}

fn removeFromList(self: *StaticAllocator, fl: Fl, sl: Sl) void {
    const block = self.free_lists[fl][sl].?; // if this fails, the bitmap has lied to us
    if (block.prev_block) |prev_block| {
        if (block.next_block) |next_block| {
            prev_block.*.next_block = next_block;
        } else {
            prev_block.*.next_block = null;
        }
    } else {
        // no more blocks in this fl/sl, update bitmap
        self.bitmapRemove(fl, sl);
    }

    self.free_lists[fl][sl] = null;
}

pub fn remove(self: *BlockHeader) void {
    if (self.prev_block) |prev_block| {
        if (self.next_block) |next_block| {
            prev_block.*.next_block = next_block;
        } else {
            prev_block.*.next_block = null;
        }
    }
}
pub fn alloc(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));

    const worst_case_n = n + @max(alignment.toByteUnits() - 1, @sizeOf(BlockHeader));
    const fl, const sl = self.findFreeLevels(worst_case_n) orelse return null;
    const block = self.free_lists[fl][sl].?; // if this fails bitmap has lied to us
    const aligned_addr = std.mem.alignBackward(u8, block.addr() + block.size - n, alignment);
    const padding = aligned_addr - block.addr();
    if (padding > 0) {
        std.debug.assert(padding > @sizeOf(BlockHeader));
        self.insertInList(block.addr(), padding);
    }

    self.removeFromList(fl, sl);
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
    // TODO: is it even possible to recapture "lost" space?
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));
    const addr = @intFromPtr(buf.ptr);
    self.insertInList(addr, buf.len);

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
