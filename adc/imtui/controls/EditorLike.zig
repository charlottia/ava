const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");
const TextMode = @import("../root.zig").TextMode;
const Source = @import("./Source.zig");

const EditorLike = @This();

pub const MAX_LINE = 255;

imtui: *Imtui,

// config
r1: usize = undefined,
c1: usize = undefined,
r2: usize = undefined,
c2: usize = undefined,

scroll_bars: bool = undefined,
tab_stops: u8 = undefined,

// state
cursor_row: usize = 0,
cursor_col: usize = 0,
scroll_row: usize = 0,
scroll_col: usize = 0,

shift_down: bool = false,
selection_start: ?struct {
    cursor_row: usize,
    cursor_col: usize,
} = null,

source: ?*Source = null,
hscrollbar: TextMode(25, 80).Hscrollbar = .{},
vscrollbar: TextMode(25, 80).Vscrollbar = .{},
dragging_text: bool = false,
cmt: ?TextMode(25, 80).ScrollbarTarget = null,

pub fn describe(self: *EditorLike, r1: usize, c1: usize, r2: usize, c2: usize) void {
    self.r1 = r1;
    self.c1 = c1;
    self.r2 = r2;
    self.c2 = c2;
    self.scroll_bars = false;
    self.tab_stops = 8;
}

fn showHScrollWhenActive(self: *const EditorLike) bool {
    return self.scroll_bars and self.r2 - self.r1 > 1;
}

fn showVScrollWhenActive(self: *const EditorLike) bool {
    return self.scroll_bars and self.r2 - self.r1 > 3;
}

pub fn handleKeyPress(self: *EditorLike, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !bool {
    const src = self.source.?;

    if (modifiers.get(.left_alt) or modifiers.get(.right_alt) or
        keycode == .left_alt or keycode == .right_alt)
        return false;

    if (modifiers.get(.left_shift) or modifiers.get(.right_shift)) {
        self.shift_down = true;
        if (self.selection_start == null)
            // We probably wanna restrict the cases this is applicable in.
            // e.g. only actually start a selection when we're moving the
            // cursor, not stopping it with the hack down in the else =>
            // below.
            self.selection_start = .{
                .cursor_row = self.cursor_row,
                .cursor_col = self.cursor_col,
            };
    } else self.shift_down = false;

    const single_mode = src.single_mode;

    switch (keycode) {
        .up => {
            if (!single_mode)
                self.cursor_row -|= 1;
            if (!self.shift_down)
                self.selection_start = null;
        },
        .down => {
            if (!single_mode and self.cursor_row < src.lines.items.len)
                self.cursor_row += 1;
            if (!self.shift_down)
                self.selection_start = null;
        },
        .left => {
            self.cursor_col -|= 1;
            if (!self.shift_down)
                self.selection_start = null;
        },
        .right => {
            if (self.cursor_col < MAX_LINE)
                self.cursor_col += 1;
            if (!self.shift_down)
                self.selection_start = null;
        },
        .home => {
            self.cursor_col = if (self.maybeCurrentLine()) |line|
                lineFirst(line.items)
            else
                0;
            if (!self.shift_down)
                self.selection_start = null;
        },
        .end => {
            self.cursor_col = if (self.maybeCurrentLine()) |line|
                line.items.len
            else
                0;
            if (!self.shift_down)
                self.selection_start = null;
        },
        .page_up => {
            if (!single_mode)
                self.pageUp();
            if (!self.shift_down)
                self.selection_start = null;
        },
        .page_down => {
            if (!single_mode)
                self.pageDown();
            if (!self.shift_down)
                self.selection_start = null;
        },
        .tab => {
            // TODO: selection behaviour
            var line = try self.currentLine();
            while (line.items.len < MAX_LINE - 1) {
                try line.insert(src.allocator, self.cursor_col, ' ');
                self.cursor_col += 1;
                if (self.cursor_col % self.tab_stops == 0)
                    break;
            }
        },
        .@"return" => {
            if (single_mode)
                return false;
            self.selection_start = null;
            try self.splitLine();
        },
        .backspace => {
            self.selection_start = null;
            try self.deleteAt(.backspace);
        },
        .delete => {
            self.selection_start = null;
            try self.deleteAt(.delete);
        },
        else => if (Imtui.Controls.isPrintableKey(keycode) and (try self.currentLine()).items.len < (MAX_LINE - 1)) {
            // XXX: involve selection in the above calculation
            if (self.selection_start) |*ss| {
                orderRowCols(&self.cursor_row, &self.cursor_col, &ss.cursor_row, &ss.cursor_col);
                try self.deleteRange(self.cursor_row, self.cursor_col, ss.cursor_row, ss.cursor_col);
                self.selection_start = null;
            }

            var line = try self.currentLine();
            if (line.items.len < self.cursor_col)
                try line.appendNTimes(src.allocator, ' ', self.cursor_col - line.items.len);
            try line.insert(src.allocator, self.cursor_col, Imtui.Controls.getCharacter(keycode, modifiers));
            self.cursor_col += 1;
        } else return false,
    }

    return true;
}

pub fn handleKeyUp(self: *EditorLike, keycode: SDL.Keycode) !void {
    if (keycode == .left_shift or keycode == .right_shift)
        self.shift_down = false;
}

pub fn handleMouseDown(self: *EditorLike, active: bool, button: SDL.MouseButton, clicks: u8, cm: bool) !bool {
    _ = clicks;

    const r = self.imtui.mouse_row;
    const c = self.imtui.mouse_col;

    if (!cm) {
        self.dragging_text = false;
        if (!self.shift_down)
            self.selection_start = null;
        self.cmt = null;

        // `<= c2` is for scrollbar.
        if (!(r >= self.r1 and r < self.r2 and c >= self.c1 and c <= self.c2))
            return false;
    } else {
        // cm

        // XXX: this used to have `and self.imtui.focusedEditor() == self`; does
        // XXX: it need `and active` now?
        if (self.dragging_text) {
            // Transform clickmatic events to drag events when dragging text so you
            // can drag to an edge and continue selecting.
            try self.handleMouseDrag(button);
            return true;
        }
    }

    if (c >= self.c1 and c < self.c2) {
        const hscroll = self.showHScrollWhenActive() and (r == self.hscrollbar.r or
            (cm and self.cmt != null and self.cmt.?.isHscr()));
        if (active and hscroll) {
            if (self.hscrollbar.hit(c, cm, self.cmt)) |hit|
                switch (hit) {
                    .left => {
                        self.cmt = .hscr_left;
                        self.selection_start = null;
                        self.hscrLeft();
                    },
                    .toward_left => {
                        // Lacks fidelity: a full "page turn" (where possible)
                        // doesn't move the cursor on the screen.
                        self.cmt = .hscr_toward_left;
                        self.selection_start = null;
                        self.cursor_col = self.scroll_col;
                        self.scroll_col = if (self.scroll_col >= (self.hscrollbar.c2 - self.hscrollbar.c1))
                            self.scroll_col - (self.hscrollbar.c2 - self.hscrollbar.c1)
                        else
                            0;
                    },
                    .thumb => {
                        self.selection_start = null;
                        self.cursor_col = self.scroll_col;
                        self.scroll_col = (self.hscrollbar.thumb * self.hscrollbar.highest + (self.hscrollbar.c2 - self.hscrollbar.c1 - 4)) / (self.hscrollbar.c2 - self.hscrollbar.c1 - 3);
                    },
                    .toward_right => {
                        // As for .toward_left.
                        self.cmt = .hscr_toward_right;
                        self.selection_start = null;
                        self.cursor_col = self.scroll_col;
                        self.scroll_col = if (self.scroll_col <= self.hscrollbar.highest - (self.hscrollbar.c2 - self.hscrollbar.c1)) self.scroll_col + (self.hscrollbar.c2 - self.hscrollbar.c1) else self.hscrollbar.highest;
                    },
                    .right => {
                        self.cmt = .hscr_right;
                        self.selection_start = null;
                        self.hscrRight();
                    },
                };
            if (self.cursor_col < self.scroll_col)
                self.cursor_col = self.scroll_col
            else if (self.cursor_col > self.scroll_col + (self.c2 - self.c1 - 1))
                self.cursor_col = self.scroll_col + (self.c2 - self.c1 - 1);
            return true;
        } else if (!cm) {
            // Implication: either we're activating this window for the
            // first time, or it's already active (and we didn't click in the
            // hscroll).

            // Consider a click where hscroll _would_ be to be a click
            // immediately above it.
            const eff_r = if (hscroll) r - 1 else r;
            self.cursor_col = self.scroll_col + c - self.c1;
            self.cursor_row = @min(self.scroll_row + eff_r - self.r1, self.source.?.lines.items.len -| 1);
            self.dragging_text = true;
            if (!self.shift_down)
                self.selection_start = .{
                    .cursor_row = self.cursor_row,
                    .cursor_col = self.cursor_col,
                };
            return true;
        }
    }

    if (r >= self.r1 and r < self.r2 - 1) {
        const vscroll = self.showVScrollWhenActive() and (c == self.vscrollbar.c or
            (cm and self.cmt != null and self.cmt.?.isVscr()));
        if (active and vscroll) {
            if (self.vscrollbar.hit(r, cm, self.cmt)) |hit|
                switch (hit) {
                    .up => {
                        self.cmt = .vscr_up;
                        self.selection_start = null;
                        self.vscrUp();
                    },
                    .toward_up => {
                        self.cmt = .vscr_toward_up;
                        self.selection_start = null;
                        self.pageUp();
                    },
                    .thumb => {
                        self.selection_start = null;
                        // ~~I can't quite get this to the exact same algorithm as
                        // QBASIC!!! Agh!! What gives!!! Daifuku!!~~
                        // nvm that got it
                        const start: f32 = @ceil(@as(f32, @floatFromInt(self.vscrollbar.highest)) *
                            @as(f32, @floatFromInt(self.vscrollbar.thumb)) /
                            @as(f32, @floatFromInt(self.vscrollbar.r2 - self.vscrollbar.r1 - 2 - 1)));
                        self.cursor_row = @intFromFloat(start);
                        self.scroll_row = @intFromFloat(start);
                    },
                    .toward_down => {
                        self.cmt = .vscr_toward_down;
                        self.selection_start = null;
                        self.pageDown();
                    },
                    .down => {
                        self.cmt = .vscr_down;
                        self.selection_start = null;
                        self.vscrDown();
                    },
                };
            return true;
        }
    }

    return false;
}

pub fn handleMouseDrag(self: *EditorLike, b: SDL.MouseButton) !void {
    _ = b;

    if (self.dragging_text) {
        const hscroll = self.showHScrollWhenActive();

        if (self.imtui.mouse_col < self.c1)
            self.hscrLeft()
        else if (self.imtui.mouse_col >= self.c2)
            self.hscrRight()
        else if (self.imtui.mouse_row < self.r1)
            self.vscrUp()
        else if (self.imtui.mouse_row >= self.r2 - @intFromBool(hscroll))
            self.vscrDown()
        else if (self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col <= self.c2 - 1) {
            self.cursor_col = self.scroll_col + self.imtui.mouse_col - self.c1;
            self.cursor_row = @min(
                self.scroll_row + self.imtui.mouse_row -| self.r1,
                self.source.?.lines.items.len -| 1, // deny virtual line if possible
            );
        }
    }
}

fn hscrLeft(self: *EditorLike) void {
    if (self.scroll_col > 0) {
        self.scroll_col -= 1;
        self.cursor_col -= 1;
    }
}

fn hscrRight(self: *EditorLike) void {
    if (self.scroll_col < (MAX_LINE - (self.c2 - self.c1 - 1))) {
        self.scroll_col += 1;
        self.cursor_col += 1;
    }
}

fn vscrUp(self: *EditorLike) void {
    if (self.source.?.single_mode) return;
    if (self.scroll_row > 0) {
        if (self.cursor_row == self.scroll_row + self.r2 - self.r1 - 2)
            self.cursor_row -= 1;
        self.scroll_row -= 1;
    }
}

fn vscrDown(self: *EditorLike) void {
    if (self.source.?.single_mode) return;
    // Ask me about the pages in my diary required to work this condition out!
    if (self.scroll_row < self.source.?.lines.items.len -| (self.r2 - self.r1 - 1 - 1)) {
        if (self.cursor_row == self.scroll_row)
            self.cursor_row += 1;
        self.scroll_row += 1;
    }
}

fn currentLine(self: *EditorLike) !*std.ArrayListUnmanaged(u8) {
    const src = self.source.?;
    if (self.cursor_row == src.lines.items.len)
        try src.lines.append(src.allocator, .{});
    return &src.lines.items[self.cursor_row];
}

fn maybeCurrentLine(self: *EditorLike) ?*std.ArrayListUnmanaged(u8) {
    const src = self.source.?;
    if (self.cursor_row == src.lines.items.len)
        return null;
    return &src.lines.items[self.cursor_row];
}

fn splitLine(self: *EditorLike) !void {
    const src = self.source.?;

    var line = try self.currentLine();
    const first = lineFirst(line.items);
    var next = std.ArrayListUnmanaged(u8){};
    try next.appendNTimes(src.allocator, ' ', first);

    const appending = if (self.cursor_col < line.items.len) line.items[self.cursor_col..] else "";
    try next.appendSlice(src.allocator, std.mem.trimLeft(u8, appending, " "));
    if (line.items.len > self.cursor_col)
        try line.replaceRange(src.allocator, self.cursor_col, line.items.len - self.cursor_col, &.{});
    try src.lines.insert(src.allocator, self.cursor_row + 1, next);

    self.cursor_col = first;
    self.cursor_row += 1;
}

fn deleteAt(self: *EditorLike, mode: enum { backspace, delete }) !void {
    const src = self.source.?;

    if (mode == .backspace and self.cursor_col == 0) {
        if (self.cursor_row == 0 or src.single_mode) {
            //  WRONG  //
            //   WAY   //
            // GO BACK //
            return;
        }

        if (self.cursor_row == src.lines.items.len) {
            self.cursor_row -= 1;
            self.cursor_col = @intCast((try self.currentLine()).items.len);
        } else {
            var removed = src.lines.orderedRemove(self.cursor_row);
            self.cursor_row -= 1;
            self.cursor_col = @intCast((try self.currentLine()).items.len);
            try (try self.currentLine()).appendSlice(src.allocator, removed.items);
            removed.deinit(src.allocator);
        }
    } else if (mode == .backspace) {
        // self.cursor_col > 0
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
            try line.replaceRange(src.allocator, 0, first - back_to, &.{});
            self.cursor_col = back_to;
        } else {
            if (self.cursor_col - 1 < line.items.len)
                _ = line.orderedRemove(self.cursor_col - 1);
            self.cursor_col -= 1;
        }
    } else if (self.cursor_col >= (try self.currentLine()).items.len) {
        // mode == .delete
        if (self.cursor_row == src.lines.items.len - 1 or src.single_mode)
            return;

        var removed = src.lines.orderedRemove(self.cursor_row + 1);
        try (try self.currentLine()).appendSlice(src.allocator, removed.items);
        removed.deinit(src.allocator);
    } else {
        // mode == .delete, self.cursor_col < (try self.currentLine()).items.len
        _ = (try self.currentLine()).orderedRemove(self.cursor_col);
    }
}

fn orderRowCols(rx: *usize, cx: *usize, ry: *usize, cy: *usize) void {
    if (rx.* < ry.*) {
        // already ordered.
    } else if (rx.* > ry.*) {
        std.mem.swap(usize, rx, ry);
        std.mem.swap(usize, cx, cy);
    } else if (cx.* > cy.*) {
        std.mem.swap(usize, cx, cy);
    }
}

fn deleteRange(self: *EditorLike, r1: usize, c1: usize, r2: usize, c2: usize) !void {
    std.debug.assert(r1 < r2 or (r1 == r2 and c1 <= c2));

    // Let's just do within-lines for now.
    // TODO: multiline delete.
    std.debug.assert(r1 == r2);

    var line = try self.currentLine();
    if (c1 >= line.items.len)
        // entirely virtual
        return;
    const len = @min(line.items.len - c1, c2 - c1);
    try line.replaceRange(self.imtui.allocator, c1, len, &.{});
}

fn pageUp(self: *EditorLike) void {
    const decrement = self.r2 - self.r1 - 1;
    if (self.scroll_row == 0)
        return;

    self.scroll_row -|= decrement;
    self.cursor_row -|= decrement;
}

fn pageDown(self: *EditorLike) void {
    const increment = self.r2 - self.r1 - 1;
    if (self.scroll_row + increment >= self.source.?.lines.items.len)
        return;

    self.scroll_row += increment;
    self.cursor_row = @min(self.cursor_row + increment, self.source.?.lines.items.len - 1);
}

fn lineFirst(line: []const u8) usize {
    for (line, 0..) |c, i|
        if (c != ' ')
            return i;
    return 0;
}

pub fn draw(self: *EditorLike, active: bool, colnorminv: u8) void {
    const adjust: usize = 1 + @as(usize, @intFromBool(self.showHScrollWhenActive()));
    if (self.cursor_row < self.scroll_row) {
        self.scroll_row = self.cursor_row;
    } else if (self.r2 - self.r1 >= 1 and self.cursor_row > self.scroll_row + self.r2 - self.r1 - adjust) {
        self.scroll_row = self.cursor_row + adjust - (self.r2 - self.r1);
    }

    if (self.cursor_col < self.scroll_col) {
        self.scroll_col = self.cursor_col;
    } else if (self.cursor_col > self.scroll_col + (self.c2 - self.c1 - 1)) {
        self.scroll_col = self.cursor_col - (self.c2 - self.c1 - 1);
    }

    const src = self.source.?;

    for (0..@min(self.r2 - self.r1, src.lines.items.len - self.scroll_row)) |y| {
        if (self.selection_start) |shf| if (shf.cursor_row == self.cursor_row) {
            if (self.scroll_row + y == self.cursor_row) {
                if (self.cursor_col < shf.cursor_col)
                    // within-line, to left of origin
                    // origin may be off-screen to right
                    self.imtui.text_mode.paint(
                        y + self.r1,
                        self.c1 + self.cursor_col - self.scroll_col,
                        y + self.r1 + 1,
                        @min(self.c2, self.c1 + shf.cursor_col - self.scroll_col),
                        colnorminv,
                        .Blank,
                    )
                else
                    // within-line, on or to right of origin
                    // origin may be off-screen to left
                    self.imtui.text_mode.paint(
                        y + self.r1,
                        @max(self.c1, (self.c1 + shf.cursor_col) -| self.scroll_col),
                        y + self.r1 + 1,
                        self.c1 + self.cursor_col - self.scroll_col,
                        colnorminv,
                        .Blank,
                    );
            }
        } else {
            if (self.scroll_row + y >= @min(self.cursor_row, shf.cursor_row) and
                self.scroll_row + y <= @max(self.cursor_row, shf.cursor_row))
            {
                self.imtui.text_mode.paint(y + self.r1, self.c1, y + self.r1 + 1, self.c2, colnorminv, .Blank);
            }
        };
        const line = &src.lines.items[self.scroll_row + y];
        const upper = @min(line.items.len, self.c2 - self.c1 + self.scroll_col);
        if (upper > self.scroll_col)
            self.imtui.text_mode.write(y + self.r1, self.c1, line.items[self.scroll_col..upper]);
    }

    if (active and self.showHScrollWhenActive()) {
        self.hscrollbar = self.imtui.text_mode.hscrollbar(self.r2 - 1, self.c1, self.c2, self.scroll_col, MAX_LINE - (self.c2 - self.c1 - 1));
    }

    if (active and self.showVScrollWhenActive()) {
        self.vscrollbar = self.imtui.text_mode.vscrollbar(self.c2, self.r1, self.r2 - 1, self.cursor_row, self.source.?.lines.items.len);
    }

    if (active) {
        self.imtui.text_mode.cursor_inhibit = self.imtui.text_mode.cursor_inhibit or (self.r2 - self.r1 == 0);
        self.imtui.text_mode.cursor_row = self.cursor_row - self.scroll_row + self.r1;
        self.imtui.text_mode.cursor_col = self.cursor_col - self.scroll_col + self.c1;
    }
}
