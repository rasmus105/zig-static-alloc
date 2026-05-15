const std = @import("std");
const TlsfAllocator = @import("TlsfAllocator.zig");
const corpus = @import("fuzz_corpus");

test "basic allocator fuzz" {
    try std.testing.fuzz(
        {},
        basicFuzzTest,
        .{ .corpus = &.{
            corpus.basic_allocator_fuzz_crash001,
            corpus.basic_allocator_fuzz_crash002,
        } },
    );
}

fn basicFuzzTest(_: void, smith: *std.testing.Smith) !void {
    const buffer_size = smith.valueRangeAtMost(u32, 256, 64 * 1024);

    const backing_buffer = try std.testing.allocator.alloc(u8, buffer_size);
    defer std.testing.allocator.free(backing_buffer);

    var tlsf = TlsfAllocator.init(backing_buffer);
    const allocator = tlsf.allocator();

    const steps = smith.valueRangeAtMost(u32, 1, 512);

    for (0..steps) |_| {
        const allocation_size = smith.valueRangeAtMost(u32, 1, buffer_size / 2);

        const mem = allocator.alloc(u8, allocation_size) catch |err| switch (err) {
            error.OutOfMemory => continue,
        };

        // Touch the memory. This helps catch invalid returned pointers,
        // bad bounds, overlapping allocations in some cases, etc.
        @memset(mem, 0xEA);

        allocator.free(mem);
    }
}
