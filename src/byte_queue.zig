const std = @import("std");

pub fn ByteQueue(comptime size: usize) type {
    if (size <= @sizeOf(usize)) @compileError("ByteQueue size must be greater than architecture size!");

    return struct {
        buf: [size]u8,
        head: usize = 0,
        tail: usize = 0,
        _count: usize = 0,
        _bytes_used: usize = 0,

        const Self = @This();
        const len_size = @sizeOf(usize);

        const Error = error{
            QueueFull,
            OutputTooSmall,
        };

        pub fn init() Self {
            return Self{ .buf = undefined };
        }

        pub fn enqueue(self: *Self, item: []const u8) Error!void {
            const needed = len_size + item.len;
            if (needed > size - self._bytes_used) return error.QueueFull;

            self.write(std.mem.asBytes(&item.len));
            self.write(item);
            self._bytes_used += needed;
            self._count += 1;
        }

        pub fn dequeue(self: *Self, out: []u8) Error!?[]const u8 {
            if (self._count == 0) return null;

            const item_len = self.peekLen();
            if (out.len < item_len) return error.OutputTooSmall;

            self.head = (self.head + len_size) % size;
            self.read(out[0..item_len]);
            self._bytes_used -= len_size + item_len;
            self._count -= 1;

            return out[0..item_len];
        }

        pub fn count(self: *const Self) usize {
            return self._count;
        }

        pub fn bytesUsed(self: *const Self) usize {
            return self._bytes_used;
        }

        fn peekLen(self: *const Self) usize {
            var item_len: usize = undefined;
            var index = self.head;
            for (std.mem.asBytes(&item_len)) |*byte| {
                byte.* = self.buf[index];
                index = (index + 1) % size;
            }
            return item_len;
        }

        fn write(self: *Self, bytes: []const u8) void {
            for (bytes) |byte| {
                self.buf[self.tail] = byte;
                self.tail = (self.tail + 1) % size;
            }
        }

        fn read(self: *Self, out: []u8) void {
            for (out) |*byte| {
                byte.* = self.buf[self.head];
                self.head = (self.head + 1) % size;
            }
        }
    };
}

test ByteQueue {
    const MyQueue = ByteQueue(64);
    var instance = MyQueue.init();

    try instance.enqueue("hello");
    try instance.enqueue("a longer message");
    try instance.enqueue(&.{ 1, 2, 3, 4 });

    try std.testing.expectEqual(3, instance.count());
    try std.testing.expectEqual(@sizeOf(usize) * 3 + 5 + 16 + 4, instance.bytesUsed());

    var out: [32]u8 = undefined;
    try std.testing.expectEqualStrings("hello", (try instance.dequeue(&out)).?);
    try std.testing.expectEqualStrings("a longer message", (try instance.dequeue(&out)).?);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, (try instance.dequeue(&out)).?);
    try std.testing.expectEqual(null, try instance.dequeue(&out));
}

test "ByteQueue full" {
    const MyQueue = ByteQueue(16);
    var instance = MyQueue.init();

    try instance.enqueue("abcdefgh");
    try std.testing.expectError(error.QueueFull, instance.enqueue("x"));
}

test "ByteQueue output too small does not dequeue" {
    const MyQueue = ByteQueue(32);
    var instance = MyQueue.init();

    try instance.enqueue("hello");

    var too_small: [4]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, instance.dequeue(&too_small));
    try std.testing.expectEqual(1, instance.count());

    var out: [5]u8 = undefined;
    try std.testing.expectEqualStrings("hello", (try instance.dequeue(&out)).?);
}

test "ByteQueue wraps" {
    const MyQueue = ByteQueue(32);
    var instance = MyQueue.init();

    try instance.enqueue("1234");
    try instance.enqueue("5678");

    var out: [8]u8 = undefined;
    try std.testing.expectEqualStrings("1234", (try instance.dequeue(&out)).?);

    try instance.enqueue("abcdef");

    try std.testing.expectEqualStrings("5678", (try instance.dequeue(&out)).?);
    try std.testing.expectEqualStrings("abcdef", (try instance.dequeue(&out)).?);
}
