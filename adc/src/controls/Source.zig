const std = @import("std");
const Allocator = std.mem.Allocator;

const Source = @This();

allocator: Allocator,
ref_count: usize,
single_mode: bool = false,
title: []const u8,
lines: std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)),

pub fn createUntitledDocument(allocator: Allocator) !*Source {
    const s = try allocator.create(Source);
    errdefer allocator.destroy(s);
    s.* = .{
        .allocator = allocator,
        .ref_count = 1,
        .title = try allocator.dupe(u8, "Untitled"),
        .lines = .{},
    };
    return s;
}

pub fn createImmediateDocument(allocator: Allocator) !*Source {
    const s = try allocator.create(Source);
    errdefer allocator.destroy(s);
    s.* = .{
        .allocator = allocator,
        .ref_count = 1,
        .title = try allocator.dupe(u8, "Immediate"),
        .lines = .{},
    };
    return s;
}

pub fn createDocumentFromFile(allocator: Allocator, filename: []const u8) !*Source {
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

pub fn createSingleLine(allocator: Allocator) !*Source {
    const s = try allocator.create(Source);
    errdefer allocator.destroy(s);

    var lines = std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)){};
    try lines.append(allocator, std.ArrayListUnmanaged(u8){});

    s.* = .{
        .allocator = allocator,
        .ref_count = 1,
        .single_mode = true,
        .title = "",
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
