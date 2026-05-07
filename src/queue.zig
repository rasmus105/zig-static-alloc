const std = @import("std");

pub fn Queue(comptime T: type, comptime size: usize) type {
    return struct {
        buf: [size]T,
        head: usize = 0,
        tail: usize = 0,
        _count: usize = 0, // to allow for up to `size` items.

        const Self = @This();

        const Error = error{
            QueueFull,
        };

        pub fn init() Self {
            return Self{ .buf = undefined };
        }

        pub fn enqueue(self: *Self, item: T) Error!void {
            if (self._count == size) return error.QueueFull;

            self.buf[self.tail] = item;
            self.tail = (self.tail + 1) % size;
            self._count += 1;
        }

        pub fn dequeue(self: *Self) ?T {
            if (self._count == 0) return null;

            self._count -= 1;
            defer self.head += 1;
            return self.buf[self.head];
        }

        pub fn count(self: *const Self) usize {
            return self._count;
        }
    };
}

test Queue {
    const MyQueue = Queue(u8, 5);
    var instance = MyQueue.init();

    try instance.enqueue(1);
    try instance.enqueue(2);
    try instance.enqueue(3);
    try instance.enqueue(4);
    try instance.enqueue(5);
    try std.testing.expectError(error.QueueFull, instance.enqueue(99));
    try std.testing.expectEqual(1, instance.dequeue());
    try std.testing.expectEqual(2, instance.dequeue());
    try std.testing.expectEqual(3, instance.dequeue());
    try std.testing.expectEqual(4, instance.dequeue());
    try std.testing.expectEqual(5, instance.dequeue());
}
