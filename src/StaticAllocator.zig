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

    pub fn init(addr: usize, prev_block: ?*BlockHeader) *BlockHeader {
        const ptr: *BlockHeader = @ptrFromInt(addr);
        ptr.* = BlockHeader{
            .next_block = null,
            .prev_block = prev_block,
        };
        return ptr;
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
//
// Fl = log2(max_block_size) * log2(lowerBoundOf(size))
fn sizeToFl(self: *const StaticAllocator, size: usize) Fl {
    return std.math.log2(self.max_block_size) * std.math.log2(lowerBound(size));
}

// 356 => (lower bound) => 256
// 256 / SL_COUNT = 32
// (356 - 256) / 32 =
//
// Sl = (size-lowerBoundOf(size)) / (lowerBoundOf(size) / SL_COUNT)
// where:
//  lowerBoundOf(size) = 2^(floor(log2(size)))
fn sizeToSl(_: *const StaticAllocator, size: usize) Sl {
    const lower_bound = lowerBound(size);
    return @divTrunc((size - lower_bound), (lower_bound / SL_COUNT));
}

// size =
// (have to reverse above equations)
fn flToSize(self: *const StaticAllocator, fl: Fl) usize {
    return TODO;
}

// ====================================================================================================
// Methods - "high level"
// ====================================================================================================

fn findLevels(self: *const StaticAllocator, size: usize) struct { Fl, Sl } {
    const min_fl = self.sizeToFl(size);
    const min_sl = self.sizeToSl(size);

    const leading_zeroes_fl = @clz(self.fl_bitmap << min_fl);
    const fl = min_fl + leading_zeroes_fl;
    const leading_zeroes_sl = @clz(self.sl_bitmaps[fl] << min_sl);
    const sl = min_sl + leading_zeroes_sl;

    std.debug.assert(fl <= std.math.maxInt(Fl));
    std.debug.assert(sl <= std.math.maxInt(Sl));

    return .{ @as(Fl, @intCast(fl)), @as(Sl, @intCast(sl)) };
}

fn sizeFromLevels(self: *const StaticAllocator, sl: Sl, fl: Fl) usize {
    const lower_bound_size = self.flToSize(fl);
    return (lower_bound_size / SL_COUNT) * sl + lower_bound_size;
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

pub fn alloc(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
    const self: *StaticAllocator = @ptrCast(@alignCast(ctx));

    const fl, const sl = self.findLevels(n);
    const list = self.free_lists[fl][sl] orelse std.process.fatal("Allocator lib bug: Bitmap does not match list! (size={d}, alignment='{s}', ret_addr={X:0>8})\n", .{ n, @tagName(alignment), return_address });
    list.remove();
    const allocation_addr = @as([*]u8, @ptrCast(list));
    const move = std.mem.alignForward(usize, @intFromPtr(allocation_addr), alignment.toByteUnits());

    if (move > @sizeOf(BlockHeader)) {
        // update list to contain this new free block of memory.

    }
    // if `move > 0` and `move < @sizeOf(BlockHeader)` this free memory should be recaptured upon freeing.

    const block_size = self.sizeFromLevels(fl, sl);
    const remaining_space = block_size - n;

    // we might have more than 0 bytes left, but less than `@sizeOf(BlockHeader)`, in which
    // case these bytes are temporarily lost and should be "recaptured" in `free`.
    if (remaining_space > @sizeOf(BlockHeader)) {
        const fl_new, const sl_new = self.findLevels(remaining_space);
        const new_block_addr = @intFromPtr(list) + remaining_space;
        if (self.free_lists[fl_new][sl_new]) |prev| {
            list.next_block = BlockHeader.init(new_block_addr, prev);
        } else {
            self.free_lists[fl_new][sl_new] = BlockHeader.init(new_block_addr, null);
        }
    }

    self.free_lists[fl][sl] = null; // clear now used list
    return allocation_addr + move;
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
