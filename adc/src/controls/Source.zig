const std = @import("std");
const Allocator = std.mem.Allocator;

const Source = @This();

allocator: Allocator,
ref_count: usize,
title: []const u8,

lines: std.ArrayList(std.ArrayList(u8)),

pub fn createUntitled(allocator: Allocator) !*Source {
    const s = try allocator.create(Source);
    errdefer allocator.destroy(s);
    s.* = .{
        .allocator = allocator,
        .ref_count = 1,
        .title = try allocator.dupe(u8, "Untitled"),
        .lines = std.ArrayList(std.ArrayList(u8)).init(allocator),
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
        .lines = std.ArrayList(std.ArrayList(u8)).init(allocator),
    };
    return s;
}

pub fn createFromFile(allocator: Allocator, filename: []const u8) !*Source {
    const s = try allocator.create(Source);
    errdefer allocator.destroy(s);

    var lines = std.ArrayList(std.ArrayList(u8)).init(allocator);
    errdefer {
        for (lines.items) |line| line.deinit();
        lines.deinit();
    }

    const f = try std.fs.cwd().openFile(filename, .{});
    defer f.close();

    while (try f.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 10240)) |line|
        try lines.append(std.ArrayList(u8).fromOwnedSlice(allocator, line));

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
    for (self.lines.items) |line|
        line.deinit();
    self.lines.deinit();
    self.allocator.destroy(self);
}
