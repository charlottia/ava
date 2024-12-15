const std = @import("std");
const Allocator = std.mem.Allocator;

const Source = @This();

allocator: Allocator,
ref_count: usize,
title: []const u8,

lines: std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)) = .{},

pub fn createUntitled(allocator: Allocator) !*Source {
    const s = try allocator.create(Source);
    errdefer allocator.destroy(s);
    s.* = .{
        .allocator = allocator,
        .ref_count = 1,
        .title = try allocator.dupe(u8, "Untitled"),
    };
    return s;
}

pub fn createImmediate(allocator: Allocator) !*Source {
    const s = try allocator.create(Source);
    errdefer allocator.destroy(s);
    s.* = .{
        .allocator = allocator,
        .ref_count = 1,
        .title = try allocator.dupe(u8, "Immediate"),
    };
    return s;
}

pub fn createFromFile(allocator: Allocator, filename: []const u8) !*Source {
    const s = try allocator.create(Source);
    errdefer allocator.destroy(s);

    var lines = std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)){};
    errdefer {
        for (lines.items) |*line| line.deinit(allocator);
        lines.deinit(allocator);
    }

    const f = try std.fs.cwd().openFile(filename, .{});
    defer f.close();

    while (try f.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 10240)) |line|
        try lines.append(allocator, std.ArrayListUnmanaged(u8).fromOwnedSlice(line));

    const index = std.mem.lastIndexOfScalar(u8, filename, '/');

    s.* = .{
        .allocator = allocator,
        .ref_count = 1,
        .title = try std.ascii.allocUpperString(
            allocator,
            if (index) |ix| filename[ix + 1 ..] else filename,
        ),
        .lines = lines,
    };
    return s;
}

pub fn acquire(self: *Source) void {
    self.ref_count += 1;
}

pub fn release(self: *Source) void {
    self.ref_count -= 1;
    if (self.ref_count > 0) return;

    // deinit
    self.allocator.free(self.title);
    for (self.lines.items) |*line|
        line.deinit(self.allocator);
    self.lines.deinit(self.allocator);
    self.allocator.destroy(self);
}
