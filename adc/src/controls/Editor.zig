const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

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
_hidden: bool = undefined,
_immediate: bool = undefined,

cursor_row: usize = 0,
cursor_col: usize = 0,
scroll_row: usize = 0,
scroll_col: usize = 0,
toggled_fullscreen: bool = false,
dragging_title: bool = false,
header_dragged_to: ?usize = null,

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
    self._hidden = false;
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

pub fn hidden(self: *Editor) void {
    self._hidden = true;
}

pub fn immediate(self: *Editor) void {
    self._immediate = true;
}

pub fn end(self: *Editor) void {
    if (self._last_source != self._source)
        if (self._last_source) |ls| {
            ls.release();
            self._last_source = null;
        };

    if (self._hidden or self.r1 == self.r2)
        return;

    const src = self._source.?;

    const active = self.imtui.focus_editor == self.id;

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
        // XXX: heuristic.
        self.imtui.text_mode.draw(self.r1, self.c2 - 4, 0x71, if (self.r2 - self.r1 == 23) .ArrowVertical else .ArrowUp);
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
            self.imtui.text_mode.draw(self.r1 + 2 + self.verticalScrollThumb(), self.c2 - 1, 0x00, .Blank);
            self.imtui.text_mode.draw(self.r2 - 2, self.c2 - 1, 0x70, .ArrowDown);
        }

        if (self.r2 - self.r1 > 2) {
            self.imtui.text_mode.draw(self.r2 - 1, self.c1 + 1, 0x70, .ArrowLeft);
            self.imtui.text_mode.paint(self.r2 - 1, self.c1 + 2, self.r2, self.c2 - 2, 0x70, .DotsLight);
            self.imtui.text_mode.draw(self.r2 - 1, self.c1 + 2 + self.horizontalScrollThumb(), 0x00, .Blank);
            self.imtui.text_mode.draw(self.r2 - 1, self.c2 - 2, 0x70, .ArrowRight);
        }
    }

    if (active and self.imtui.focus == .editor) {
        self.imtui.text_mode.cursor_inhibit = self.imtui.text_mode.cursor_inhibit or (self.r2 - self.r1 == 1);
        self.imtui.text_mode.cursor_col = self.cursor_col + 1 - self.scroll_col;
        self.imtui.text_mode.cursor_row = self.cursor_row + 1 - self.scroll_row + self.r1;
    }
}

pub fn mouseIsOver(self: *const Editor) bool {
    return self.imtui.mouse_row >= self.r1 and self.imtui.mouse_row < self.r2 and self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
}

pub fn handleKeyPress(self: *Editor, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    const src = self._source.?;

    switch (keycode) {
        .down => if (self.cursor_row < src.lines.items.len) {
            self.cursor_row += 1;
        },
        .up => if (self.cursor_row > 0) {
            self.cursor_row -= 1;
        },
        .left => if (self.cursor_col > 0) {
            self.cursor_col -= 1;
        },
        .right => if (self.cursor_col < MAX_LINE) {
            self.cursor_col += 1;
        },
        .home => self.cursor_col = if (self.maybeCurrentLine()) |line|
            lineFirst(line.items)
        else
            0,
        .end => self.cursor_col = if (self.maybeCurrentLine()) |line|
            line.items.len
        else
            0,
        .page_up => self.pageUp(),
        .page_down => self.pageDown(),
        .tab => {
            var line = try self.currentLine();
            while (line.items.len < MAX_LINE - 1) {
                try line.insert(self.cursor_col, ' ');
                self.cursor_col += 1;
                if (self.cursor_col % 8 == 0)
                    break;
            }
        },
        .@"return" => try self.splitLine(),
        .backspace => try self.deleteAt(.backspace),
        .delete => try self.deleteAt(.delete),
        else => if (isPrintableKey(keycode) and (try self.currentLine()).items.len < 254) {
            var line = try self.currentLine();
            if (line.items.len < self.cursor_col)
                try line.appendNTimes(' ', self.cursor_col - line.items.len);
            try line.insert(self.cursor_col, getCharacter(keycode, modifiers));
            self.cursor_col += 1;
        },
    }

    // XXX magic. this line used to be:
    // const adjust: usize = if (editor.kind == .immediate or editor.height == 1) 1 else 2;
    // XXX keypress while resizing or while empty window focussed = explode
    const adjust: usize = if (self.r2 - self.r1 - 1 <= 2) 1 else 2;
    if (self.cursor_row < self.scroll_row) {
        self.scroll_row = self.cursor_row;
    } else if (self.r2 - self.r1 > 1 and self.cursor_row > self.scroll_row + self.r2 - self.r1 - 1 - adjust) {
        self.scroll_row = self.cursor_row + adjust - (self.r2 - self.r1 - 1);
    }

    if (self.cursor_col < self.scroll_col) {
        self.scroll_col = self.cursor_col;
    } else if (self.cursor_col > self.scroll_col + (self.c2 - self.c1 - 3)) {
        self.scroll_col = self.cursor_col - (self.c2 - self.c1 - 3);
    }
}

pub fn handleMouseDown(self: *Editor, button: SDL.MouseButton, clicks: u8) !void {
    _ = button;
    _ = clicks;

    const r = self.imtui.mouse_row;
    const c = self.imtui.mouse_col;

    self.dragging_title = false;

    if (r == self.r1) {
        // Fullscreen triggers on MouseUp.
        // TODO: for this and all focus changes below, check that these won't
        // effect processing of anything else adversely. Unclear what might not
        // be anticipating a mid-frame focus change.
        self.imtui.focus_editor = self.id;
        self.dragging_title = true;
        return;
    }

    if (c > self.c1 and c < self.c2 - 1) {
        const hscroll = !self._immediate and r == self.r2 - 1;
        if (hscroll and self.imtui.focus_editor == self.id) {
            if (c == self.c1 + 1) {
                if (self.scroll_col > 0) {
                    self.scroll_col -= 1;
                    self.cursor_col -= 1;
                }
            } else if (c > self.c1 + 1 and c < self.c2 - 2) {
                const hst = self.horizontalScrollThumb();
                if (c - 2 < hst)
                    self.scroll_col = if (self.scroll_col >= (self.c2 - self.c1 - 2)) self.scroll_col - (self.c2 - self.c1 - 2) else 0
                else if (c - 2 > hst)
                    self.scroll_col = if (self.scroll_col <= MAX_LINE - (self.c2 - self.c1 - 3) - (self.c2 - self.c1 - 2)) self.scroll_col + (self.c2 - self.c1 - 2) else MAX_LINE - (self.c2 - self.c1 - 3)
                else
                    self.scroll_col = (hst * (MAX_LINE - (self.c2 - self.c1 - 3)) + (self.c2 - self.c1 - 6)) / (self.c2 - self.c1 - 5);
                self.cursor_col = self.scroll_col;
            } else if (c == self.c2 - 2) {
                if (self.scroll_col < (MAX_LINE - (self.c2 - self.c1 - 3))) {
                    self.scroll_col += 1;
                    self.cursor_col += 1;
                }
            }
            if (self.cursor_col < self.scroll_col)
                self.cursor_col = self.scroll_col
            else if (self.cursor_col > self.scroll_col + (self.c2 - self.c1 - 3))
                self.cursor_col = self.scroll_col + (self.c2 - self.c1 - 3);
        } else {
            const eff_r = if (hscroll) r - 1 else r;
            self.cursor_col = self.scroll_col + c - self.c1 - 1;
            self.cursor_row = @min(self.scroll_row + eff_r - self.r1 - 1, self._source.?.lines.items.len);
            self.imtui.focus_editor = self.id;
        }
        return;
    }

    if (self.imtui.focus_editor == self.id and !self._immediate and c == self.c2 - 1 and r > self.r1 and r < self.r2 - 1) {
        if (r == self.r1 + 1) {
            std.debug.print("^\n", .{});
        } else if (r > self.r1 + 1 and r < self.r2 - 2) {
            // TODO: Vertical scrollbar behaviour has a knack to it I don't
            // quite understand yet.  The horizontal scrollbar strictly relates
            // to the actual scroll of the window (scroll_x) --- it has nothing
            // to do with the cursor position itself (cursor_x) --- so it's
            // easy and predictable.
            //     The vertical scrollbar is totally different --- it shows the
            // cursor's position in the (virtual) document.  Thus, when using the
            // pgup/pgdn feature of it, we don't expect the thumb to go all
            // the way to the top or bottom most of the time, since that'd only
            // happen if cursor_y happened to land on 0 or self.lines.items.len.
            //
            // Let's make some observations:
            //
            // Scrolled to the very top, cursor on line 1. 1-18 are visible. (19
            //     under HSB.)
            // Clicking pgdn.
            // Now 19-36 are visible, cursor on 19.
            //
            // Scrolled to very top, cursor on line 3. 1-18 visible.
            // pgdn
            // 19-36 visible, cursor now on line 21. (not moved.)
            //
            // Actual pgup/pgdn seem to do the exact same thing.

            const vst = self.verticalScrollThumb();
            if (r - self.r1 - 2 < vst)
                self.pageUp()
            else if (r - self.r1 - 2 > vst)
                self.pageDown()
            else {
                // TODO: the thing, zhu li
                std.debug.print("X\n", .{});
            }
        } else if (r == self.r2 - 2) {
            std.debug.print("v\n", .{});
        }
        return;
    }
}

pub fn handleMouseDrag(self: *Editor, b: SDL.MouseButton) !void {
    _ = b;

    if (self.dragging_title and self.r1 != self.imtui.mouse_row) {
        self.header_dragged_to = self.imtui.mouse_row;
        return;
    }
}

pub fn handleMouseUp(self: *Editor, button: SDL.MouseButton, clicks: u8) !void {
    _ = button;

    const r = self.imtui.mouse_row;
    const c = self.imtui.mouse_col;

    if (r == self.r1) {
        if ((!self._immediate and c == self.c2 - 4) or clicks == 2)
            self.toggled_fullscreen = true;
        return;
    }
}

fn verticalScrollThumb(self: *const Editor) usize {
    return if (self._source.?.lines.items.len == 0)
        0
    else
        self.cursor_row * (self.r2 - self.r1 - 5) / self._source.?.lines.items.len;
}

fn horizontalScrollThumb(self: *const Editor) usize {
    return self.scroll_col * (self.c2 - self.c1 - 5) / (MAX_LINE - (self.c2 - self.c1 - 3));
}

pub fn toggledFullscreen(self: *Editor) bool {
    defer self.toggled_fullscreen = false;
    return self.toggled_fullscreen;
}

pub fn headerDraggedTo(self: *Editor) ?usize {
    defer self.header_dragged_to = null;
    return self.header_dragged_to;
}

fn currentLine(self: *Editor) !*std.ArrayList(u8) {
    const src = self._source.?;
    if (self.cursor_row == src.lines.items.len)
        try src.lines.append(std.ArrayList(u8).init(src.allocator));
    return &src.lines.items[self.cursor_row];
}

fn maybeCurrentLine(self: *Editor) ?*std.ArrayList(u8) {
    const src = self._source.?;
    if (self.cursor_row == src.lines.items.len)
        return null;
    return &src.lines.items[self.cursor_row];
}

pub fn splitLine(self: *Editor) !void {
    const src = self._source.?;

    var current = try self.currentLine();
    const first = lineFirst(current.items);
    var next = std.ArrayList(u8).init(src.allocator);
    try next.appendNTimes(' ', first);

    const appending = if (self.cursor_col < current.items.len) current.items[self.cursor_col..] else "";
    try next.appendSlice(std.mem.trimLeft(u8, appending, " "));
    try current.replaceRange(self.cursor_col, current.items.len - self.cursor_col, &.{});
    try src.lines.insert(self.cursor_row + 1, next);

    self.cursor_col = first;
    self.cursor_row += 1;
}

pub fn deleteAt(self: *Editor, mode: enum { backspace, delete }) !void {
    const src = self._source.?;

    if (mode == .backspace and self.cursor_col == 0) {
        if (self.cursor_row == 0) {
            //  WRONG  //
            //   WAY   //
            // GO BACK //
            return;
        }

        if (self.cursor_row == src.lines.items.len) {
            self.cursor_row -= 1;
            self.cursor_col = @intCast((try self.currentLine()).items.len);
        } else {
            const removed = src.lines.orderedRemove(self.cursor_row);
            self.cursor_row -= 1;
            self.cursor_col = @intCast((try self.currentLine()).items.len);
            try (try self.currentLine()).appendSlice(removed.items);
            removed.deinit();
        }
    } else if (mode == .backspace) {
        // self.cursor_x > 0
        const line = try self.currentLine();
        const first = lineFirst(line.items);
        if (self.cursor_col == first) {
            var back_to: usize = 0;
            if (self.cursor_row > 0) {
                var y: usize = self.cursor_row - 1;
                while (true) : (y -= 1) {
                    const lf = lineFirst(src.lines.items[y].items);
                    if (lf < first) {
                        back_to = lf;
                        break;
                    }
                    if (y == 0) break;
                }
            }
            try line.replaceRange(0, first - back_to, &.{});
            self.cursor_col = back_to;
        } else {
            if (self.cursor_col - 1 < line.items.len)
                _ = line.orderedRemove(self.cursor_col - 1);
            self.cursor_col -= 1;
        }
    } else if (self.cursor_col == (try self.currentLine()).items.len) {
        // mode == .delete
        if (self.cursor_row == src.lines.items.len - 1)
            return;

        const removed = src.lines.orderedRemove(self.cursor_row + 1);
        try (try self.currentLine()).appendSlice(removed.items);
        removed.deinit();
    } else {
        // mode == .delete, self.cursor_x < self.currentLine().items.len
        _ = (try self.currentLine()).orderedRemove(self.cursor_col);
    }
}

pub fn pageUp(self: *Editor) void {
    _ = self;
    // self.scroll_y = if (self.scroll_y >=
    std.debug.print("pgup\n", .{});
}

pub fn pageDown(self: *Editor) void {
    _ = self;
    // self.scroll_y = if (self.scroll_y >=
    std.debug.print("pgdn\n", .{});
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

fn lineFirst(line: []const u8) usize {
    for (line, 0..) |c, i|
        if (c != ' ')
            return i;
    return 0;
}

fn isPrintableKey(sym: SDL.Keycode) bool {
    return @intFromEnum(sym) >= @intFromEnum(SDL.Keycode.space) and
        @intFromEnum(sym) <= @intFromEnum(SDL.Keycode.z);
}

fn getCharacter(sym: SDL.Keycode, mod: SDL.KeyModifierSet) u8 {
    if (@intFromEnum(sym) >= @intFromEnum(SDL.Keycode.a) and
        @intFromEnum(sym) <= @intFromEnum(SDL.Keycode.z))
    {
        if (mod.get(.left_shift) or mod.get(.right_shift) or mod.get(.caps_lock)) {
            return @as(u8, @intCast(@intFromEnum(sym))) - ('a' - 'A');
        }
        return @intCast(@intFromEnum(sym));
    }

    if (mod.get(.left_shift) or mod.get(.right_shift)) {
        for (ShiftTable) |e| {
            if (e.@"0" == sym)
                return e.@"1";
        }
    }

    return @intCast(@intFromEnum(sym));
}

const ShiftTable = [_]struct { SDL.Keycode, u8 }{
    .{ .apostrophe, '"' },
    .{ .comma, '<' },
    .{ .minus, '_' },
    .{ .period, '>' },
    .{ .slash, '?' },
    .{ .@"0", ')' },
    .{ .@"1", '!' },
    .{ .@"2", '@' },
    .{ .@"3", '#' },
    .{ .@"4", '$' },
    .{ .@"5", '%' },
    .{ .@"6", '^' },
    .{ .@"7", '&' },
    .{ .@"8", '*' },
    .{ .@"9", '(' },
    .{ .semicolon, ':' },
    .{ .left_bracket, '{' },
    .{ .backslash, '|' },
    .{ .right_bracket, '}' },
    .{ .grave, '~' },
    .{ .equals, '+' },
};
