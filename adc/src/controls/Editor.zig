const std = @import("std");
const Allocator = std.mem.Allocator;
const Imtui = @import("../Imtui.zig");

const Editor = @This();

imtui: *Imtui,
generation: usize,
id: usize,
r1: usize = undefined,
c1: usize = undefined,
r2: usize = undefined,
c2: usize = undefined,
_last_source: ?*Source = undefined,
_source: ?*Source = null,
_immediate: bool = undefined,

cursor_row: usize = 0,
cursor_col: usize = 0,
scroll_row: usize = 0,
scroll_col: usize = 0,

pub const MAX_LINE = 255;

pub fn create(imtui: *Imtui, id: usize, r1: usize, c1: usize, r2: usize, c2: usize) !*Editor {
    var e = try imtui.allocator.create(Editor);
    e.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .id = id,
    };
    e.describe(r1, c1, r2, c2);
    return e;
}

pub fn describe(self: *Editor, r1: usize, c1: usize, r2: usize, c2: usize) void {
    self.r1 = r1;
    self.c1 = c1;
    self.r2 = r2;
    self.c2 = c2;
    self._last_source = self._source;
    self._source = null;
    self._immediate = false;
}

pub fn deinit(self: *Editor) void {
    if (self._last_source != self._source) {
        if (self._last_source) |ls| ls.release();
    }
    if (self._source) |s| s.release();
    self.imtui.allocator.destroy(self);
}

pub fn source(self: *Editor, s: *Source) void {
    // XXX no support for multiple calls in one frame.
    // Want to avoid repeatedly rel/acq if we end up needing to do so, already
    // have one field being written every frame.
    if (self._source != null) unreachable;

    self._source = s;
    if (self._last_source != self._source)
        s.acquire();
}

pub fn immediate(self: *Editor) void {
    self._immediate = true;
}

pub fn end(self: *Editor) void {
    if (self._last_source != self._source) {
        if (self._last_source) |ls| {
            ls.release();
            self._last_source = null;
        }
    }

    const src = self._source.?;

    const active = self.imtui.focus_editor == self.id;
    const fullscreened = false; // XXX
    const verticalScrollThumb = if (src.lines.items.len == 0) 0 else self.cursor_row * (self.r2 - self.r1 - 5) / src.lines.items.len;
    const horizontalScrollThumb = self.scroll_col * (self.c2 - self.c1 - 5) / (MAX_LINE - (self.c2 - self.c1 - 3));

    // XXX: r1==1 checks here are iffy.

    self.imtui.text_mode.draw(self.r1, self.c1, 0x17, if (self.r1 == 1) .TopLeft else .VerticalRight);
    for (self.c1 + 1..self.c2 - 1) |x|
        self.imtui.text_mode.draw(self.r1, x, 0x17, .Horizontal);

    const start = self.c1 + (self.c2 - src.title.len) / 2;
    const colour: u8 = if (active) 0x71 else 0x17;
    self.imtui.text_mode.paint(self.r1, start - 1, self.r1 + 1, start + src.title.len + 1, colour, 0);
    self.imtui.text_mode.write(self.r1, start, src.title);
    self.imtui.text_mode.draw(self.r1, self.c2 - 1, 0x17, if (self.r1 == 1) .TopRight else .VerticalLeft);

    if (!self._immediate) {
        // TODO: fullscreen control separate, rendered on top?
        self.imtui.text_mode.draw(self.r1, self.c2 - 5, 0x17, .VerticalLeft);
        self.imtui.text_mode.draw(self.r1, self.c2 - 4, 0x71, if (fullscreened) .ArrowVertical else .ArrowUp);
        self.imtui.text_mode.draw(self.r1, self.c2 - 3, 0x17, .VerticalRight);
    }

    self.imtui.text_mode.paint(self.r1 + 1, self.c1, self.r2, self.c1 + 1, 0x17, .Vertical);
    self.imtui.text_mode.paint(self.r1 + 1, self.c2 - 1, self.r2, self.c2, 0x17, .Vertical);
    self.imtui.text_mode.paint(self.r1 + 1, self.c1 + 1, self.r2, self.c2 - 1, 0x17, .Blank);

    for (0..@min(self.r2 - self.r1 - 1, src.lines.items.len - self.scroll_row)) |y| {
        const line = &src.lines.items[self.scroll_row + y];
        const upper = @min(line.items.len, self.c2 - self.c1 - 2 + self.scroll_col);
        if (upper > self.scroll_col)
            self.imtui.text_mode.write(y + self.r1 + 1, self.c1 + 1, line.items[self.scroll_col..upper]);
    }

    if (active and !self._immediate) {
        if (self.r2 - self.r1 > 4) {
            self.imtui.text_mode.draw(self.r1 + 1, self.c2 - 1, 0x70, .ArrowUp);
            self.imtui.text_mode.paint(self.r1 + 2, self.c2 - 1, self.r2 - 2, self.c2, 0x70, .DotsLight);
            self.imtui.text_mode.draw(self.r1 + 2 + verticalScrollThumb, self.c2 - 1, 0x00, .Blank);
            self.imtui.text_mode.draw(self.r2 - 2, self.c2 - 1, 0x70, .ArrowDown);
        }

        if (self.r2 - self.r1 > 2) {
            self.imtui.text_mode.draw(self.r2 - 1, self.c1 + 1, 0x70, .ArrowLeft);
            self.imtui.text_mode.paint(self.r2 - 1, self.c1 + 2, self.r2, self.c2 - 2, 0x70, .DotsLight);
            self.imtui.text_mode.draw(self.r2 - 1, self.c1 + 2 + horizontalScrollThumb, 0x00, .Blank);
            self.imtui.text_mode.draw(self.r2 - 1, self.c2 - 2, 0x70, .ArrowRight);
        }
    }

    if (active and self.imtui.focus == .editor) {
        self.imtui.text_mode.cursor_col = self.cursor_col + 1 - self.scroll_col;
        self.imtui.text_mode.cursor_row = self.cursor_row + 1 - self.scroll_row + self.r1;
    }
}

pub const Source = struct {
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
};
