const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");
const Source = @import("./Source.zig");

const Editor = @This();

pub const MAX_LINE = 255;

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,
    id: usize,
    r1: usize = undefined,
    c1: usize = undefined,
    r2: usize = undefined,
    c2: usize = undefined,
    colours: struct {
        normal: u8,
        current: u8,
        breakpoint: u8,
    } = undefined,
    scroll_bars: bool = undefined,
    tab_stops: u8 = undefined,
    last_source: ?*Source = undefined,
    source: ?*Source = null,
    hidden: bool = undefined,
    immediate: bool = undefined,

    cursor_row: usize = 0,
    cursor_col: usize = 0,
    shift_down: bool = false,
    selection_start: ?struct {
        cursor_row: usize,
        cursor_col: usize,
    } = null,
    scroll_row: usize = 0,
    scroll_col: usize = 0,
    hscrollbar: Imtui.TextMode.Hscrollbar = .{},
    vscrollbar: Imtui.TextMode.Vscrollbar = .{},
    toggled_fullscreen: bool = false,
    dragging: ?enum { header, text } = null,
    dragged_header_to: ?usize = null,
    cmt: ?Imtui.TextMode.ScrollbarTarget = null,

    pub fn describe(self: *Impl, r1: usize, c1: usize, r2: usize, c2: usize) void {
        self.r1 = r1;
        self.c1 = c1;
        self.r2 = r2;
        self.c2 = c2;
        self.colours = .{ .normal = 0x17, .current = 0x1f, .breakpoint = 0x47 };
        self.scroll_bars = false;
        self.tab_stops = 8;
        self.last_source = self.source;
        self.source = null;
        self.hidden = false;
        self.immediate = false;
    }

    pub fn deinit(self: *Impl) void {
        if (self.last_source != self.source) {
            if (self.last_source) |ls| ls.release();
        }
        if (self.source) |s| s.release();
        self.imtui.allocator.destroy(self);
    }

    pub fn showHScrollWhenActive(self: *const Impl) bool {
        return self.scroll_bars and self.r2 - self.r1 > 2;
    }

    pub fn showVScrollWhenActive(self: *const Impl) bool {
        return self.scroll_bars and self.r2 - self.r1 > 4;
    }

    pub fn isMouseOver(self: *const Impl) bool {
        return self.imtui.mouse_row >= self.r1 and self.imtui.mouse_row < self.r2 and self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
    }

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        if (keycode == .left_alt or keycode == .right_alt) {
            var mb = try self.imtui.getMenubar();
            mb.focus = .pre;
            try self.imtui.focus_stack.append(self.imtui.allocator, .{ .menubar = mb });
            return;
        }

        const src = self.source.?;

        const no_cursor = self.r2 - self.r1 <= 1;
        if (no_cursor)
            // Don't forget about this! Anything Editor-specific which doesn't get
            // disabled when the cursor is invisible needs to be above here.
            return;

        if (!(modifiers.get(.left_shift) or modifiers.get(.right_shift))) {
            // We probably wanna do this in a few more places too (like else{} below).
            self.selection_start = null;
            self.shift_down = false;
        } else {
            self.shift_down = true;
            if (self.selection_start == null)
                // We probably wanna restrict the cases this is applicable in.
                self.selection_start = .{
                    .cursor_row = self.cursor_row,
                    .cursor_col = self.cursor_col,
                };
        }

        switch (keycode) {
            .up => self.cursor_row -|= 1,
            .down => if (self.cursor_row < src.lines.items.len) {
                self.cursor_row += 1;
            },
            .left => self.cursor_col -|= 1,
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
                    try line.insert(src.allocator, self.cursor_col, ' ');
                    self.cursor_col += 1;
                    if (self.cursor_col % self.tab_stops == 0)
                        break;
                }
            },
            .@"return" => try self.splitLine(),
            .backspace => try self.deleteAt(.backspace),
            .delete => try self.deleteAt(.delete),
            else => if (isPrintableKey(keycode) and (try self.currentLine()).items.len < (MAX_LINE - 1)) {
                var line = try self.currentLine();
                if (line.items.len < self.cursor_col)
                    try line.appendNTimes(src.allocator, ' ', self.cursor_col - line.items.len);
                try line.insert(src.allocator, self.cursor_col, getCharacter(keycode, modifiers));
                self.cursor_col += 1;
            },
        }
    }

    pub fn handleKeyUp(self: *Impl, keycode: SDL.Keycode) !void {
        if (keycode == .left_shift or keycode == .right_shift)
            self.shift_down = false;
    }

    pub fn handleMouseDown(self: *Impl, button: SDL.MouseButton, clicks: u8, cm: bool) !bool {
        _ = clicks;

        const r = self.imtui.mouse_row;
        const c = self.imtui.mouse_col;

        if (!cm) {
            self.dragging = null;
            if (!self.shift_down)
                self.selection_start = null;
            self.cmt = null;

            if (!(r >= self.r1 and r < self.r2 and c >= self.c1 and c < self.c2))
                return false;
        }

        if (cm and self.imtui.focus_editor == self.id and self.dragging == .text) {
            // Transform clickmatic events to drag events when dragging text so you
            // can drag to an edge and continue selecting.
            try self.handleMouseDrag(button);
            return true;
        }

        if (r == self.r1) {
            if (!cm) {
                // Fullscreen triggers on MouseUp, not here.
                self.imtui.focus_editor = self.id;
                self.dragging = .header;
            }
            return true;
        }

        if (c > self.c1 and c < self.c2 - 1) {
            const hscroll = self.showHScrollWhenActive() and (r == self.hscrollbar.r or
                (cm and self.cmt != null and self.cmt.?.isHscr()));
            if (self.imtui.focus_editor == self.id and hscroll) {
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
                else if (self.cursor_col > self.scroll_col + (self.c2 - self.c1 - 3))
                    self.cursor_col = self.scroll_col + (self.c2 - self.c1 - 3);
                return true;
            } else if (!cm) {
                // Implication: either we're focussing this window for the first
                // time, or it's already focused (and we didn't click in the
                // hscroll).
                if (self.imtui.focus_editor != self.id) {
                    self.imtui.focus_editor = self.id;
                    // Remove any other editors' selections.
                    var cit = self.imtui.controls.valueIterator();
                    while (cit.next()) |control| {
                        switch (control.*) {
                            .editor => |e| if (e != self) {
                                e.selection_start = null;
                            },
                            else => {},
                        }
                    }
                }

                // Consider a click where hscroll _would_ be to be a click
                // immediately above it.
                const eff_r = if (hscroll) r - 1 else r;
                self.cursor_col = self.scroll_col + c - self.c1 - 1;
                self.cursor_row = @min(self.scroll_row + eff_r - self.r1 - 1, self.source.?.lines.items.len -| 1);
                self.dragging = .text;
                if (!self.shift_down)
                    self.selection_start = .{
                        .cursor_row = self.cursor_row,
                        .cursor_col = self.cursor_col,
                    };
                return true; // XXX Menu/Bar
            }
        }

        if (r > self.r1 and r < self.r2 - 1) {
            const vscroll = self.showVScrollWhenActive() and (c == self.vscrollbar.c or
                (cm and self.cmt != null and self.cmt.?.isVscr()));
            if (self.imtui.focus_editor == self.id and vscroll) {
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

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        _ = b;

        if (self.dragging == .header and self.r1 != self.imtui.mouse_row) {
            self.dragged_header_to = self.imtui.mouse_row;
            return;
        }

        if (self.dragging == .text) {
            const hscroll = self.showHScrollWhenActive();

            if (self.imtui.mouse_col <= self.c1)
                self.hscrLeft()
            else if (self.imtui.mouse_col >= self.c2 - 1)
                self.hscrRight()
            else if (self.imtui.mouse_row <= self.r1)
                self.vscrUp()
            else if (self.imtui.mouse_row >= self.r2 - @intFromBool(hscroll))
                self.vscrDown()
            else if (self.imtui.mouse_col > self.c1 and self.imtui.mouse_col < self.c2 - 1 and
                self.imtui.mouse_row != self.r1)
            {
                self.cursor_col = self.scroll_col + self.imtui.mouse_col - self.c1 - 1;
                self.cursor_row = @min(
                    self.scroll_row + self.imtui.mouse_row -| self.r1 -| 1,
                    self.source.?.lines.items.len -| 1, // deny virtual line if possible
                );
            }
            return;
        }
    }

    pub fn handleMouseUp(self: *Impl, button: SDL.MouseButton, clicks: u8) !void {
        _ = button;

        const r = self.imtui.mouse_row;
        const c = self.imtui.mouse_col;

        if (r == self.r1) {
            if ((!self.immediate and c == self.c2 - 4) or clicks == 2)
                self.toggled_fullscreen = true;
            return;
        }
    }

    fn hscrLeft(self: *Impl) void {
        if (self.scroll_col > 0) {
            self.scroll_col -= 1;
            self.cursor_col -= 1;
        }
    }

    fn hscrRight(self: *Impl) void {
        if (self.scroll_col < (MAX_LINE - (self.c2 - self.c1 - 3))) {
            self.scroll_col += 1;
            self.cursor_col += 1;
        }
    }

    fn vscrUp(self: *Impl) void {
        if (self.scroll_row > 0) {
            if (self.cursor_row == self.scroll_row + self.r2 - self.r1 - 3)
                self.cursor_row -= 1;
            self.scroll_row -= 1;
        }
    }

    fn vscrDown(self: *Impl) void {
        // Ask me about the pages in my diary required to work this condition out!
        if (self.scroll_row < self.source.?.lines.items.len -| (self.r2 - self.r1 - 2 - 1)) {
            if (self.cursor_row == self.scroll_row)
                self.cursor_row += 1;
            self.scroll_row += 1;
        }
    }

    fn currentLine(self: *Impl) !*std.ArrayListUnmanaged(u8) {
        const src = self.source.?;
        if (self.cursor_row == src.lines.items.len)
            try src.lines.append(src.allocator, .{});
        return &src.lines.items[self.cursor_row];
    }

    fn maybeCurrentLine(self: *Impl) ?*std.ArrayListUnmanaged(u8) {
        const src = self.source.?;
        if (self.cursor_row == src.lines.items.len)
            return null;
        return &src.lines.items[self.cursor_row];
    }

    pub fn splitLine(self: *Impl) !void {
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

    pub fn deleteAt(self: *Impl, mode: enum { backspace, delete }) !void {
        const src = self.source.?;

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
            if (self.cursor_row == src.lines.items.len - 1)
                return;

            var removed = src.lines.orderedRemove(self.cursor_row + 1);
            try (try self.currentLine()).appendSlice(src.allocator, removed.items);
            removed.deinit(src.allocator);
        } else {
            // mode == .delete, self.cursor_col < (try self.currentLine()).items.len
            _ = (try self.currentLine()).orderedRemove(self.cursor_col);
        }
    }

    pub fn pageUp(self: *Impl) void {
        const decrement = self.r2 - self.r1 - 2;
        if (self.scroll_row == 0)
            return;

        self.scroll_row -|= decrement;
        self.cursor_row -|= decrement;
    }

    pub fn pageDown(self: *Impl) void {
        const increment = self.r2 - self.r1 - 2;
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
};

impl: *Impl,

pub fn create(imtui: *Imtui, id: usize, r1: usize, c1: usize, r2: usize, c2: usize) !Editor {
    var e = try imtui.allocator.create(Impl);
    e.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .id = id,
    };
    e.describe(r1, c1, r2, c2);
    return .{ .impl = e };
}

pub fn colours(self: Editor, normal: u8, current: u8, breakpoint: u8) void {
    self.impl.colours = .{
        .normal = normal,
        .current = current,
        .breakpoint = breakpoint,
    };
}

pub fn scroll_bars(self: Editor, shown: bool) void {
    self.impl.scroll_bars = shown;
}

pub fn tab_stops(self: Editor, n: u8) void {
    self.impl.tab_stops = n;
}

pub fn source(self: Editor, s: *Source) void {
    // XXX no support for multiple calls in one frame.
    // Want to avoid repeatedly rel/acq if we end up needing to do so, already
    // have one field being written every frame.
    if (self.impl.source != null) unreachable;

    self.impl.source = s;
    if (self.impl.last_source != self.impl.source)
        s.acquire();
}

pub fn hidden(self: Editor) void {
    self.impl.hidden = true;
}

pub fn immediate(self: Editor) void {
    self.impl.immediate = true;
}

pub fn end(self: Editor) void {
    const impl = self.impl;

    if (impl.last_source != impl.source)
        if (impl.last_source) |ls| {
            ls.release();
            impl.last_source = null;
        };

    if (impl.hidden or impl.r1 == impl.r2)
        return;

    const adjust: usize = 1 + @as(usize, @intFromBool(impl.showHScrollWhenActive()));
    if (impl.cursor_row < impl.scroll_row) {
        impl.scroll_row = impl.cursor_row;
    } else if (impl.r2 - impl.r1 > 1 and impl.cursor_row > impl.scroll_row + impl.r2 - impl.r1 - 1 - adjust) {
        impl.scroll_row = impl.cursor_row + adjust - (impl.r2 - impl.r1 - 1);
    }

    if (impl.cursor_col < impl.scroll_col) {
        impl.scroll_col = impl.cursor_col;
    } else if (impl.cursor_col > impl.scroll_col + (impl.c2 - impl.c1 - 3)) {
        impl.scroll_col = impl.cursor_col - (impl.c2 - impl.c1 - 3);
    }

    const src = impl.source.?;

    const active = impl.imtui.focus_editor == impl.id;

    // XXX: r1==1 checks here are iffy.

    const colnorm = impl.colours.normal;
    const colnorminv = ((colnorm & 0x0f) << 4) | ((colnorm & 0xf0) >> 4);

    impl.imtui.text_mode.draw(impl.r1, impl.c1, colnorm, if (impl.r1 == 1) .TopLeft else .VerticalRight);
    for (impl.c1 + 1..impl.c2 - 1) |x|
        impl.imtui.text_mode.draw(impl.r1, x, colnorm, .Horizontal);

    const start = impl.c1 + (impl.c2 - impl.c1 - 1 - src.title.len) / 2;
    const colour: u8 = if (active) colnorminv else colnorm;
    impl.imtui.text_mode.paint(impl.r1, start - 1, impl.r1 + 1, start + src.title.len + 1, colour, 0);
    impl.imtui.text_mode.write(impl.r1, start, src.title);
    impl.imtui.text_mode.draw(impl.r1, impl.c2 - 1, colnorm, if (impl.r1 == 1) .TopRight else .VerticalLeft);

    if (!impl.immediate) {
        // TODO: fullscreen control separate, rendered on top?
        impl.imtui.text_mode.draw(impl.r1, impl.c2 - 5, colnorm, .VerticalLeft);
        // XXX: heuristic.
        impl.imtui.text_mode.draw(impl.r1, impl.c2 - 4, colnorminv, if (impl.r2 - impl.r1 == 23) .ArrowVertical else .ArrowUp);
        impl.imtui.text_mode.draw(impl.r1, impl.c2 - 3, colnorm, .VerticalRight);
    }

    impl.imtui.text_mode.paint(impl.r1 + 1, impl.c1, impl.r2, impl.c1 + 1, colnorm, .Vertical);
    impl.imtui.text_mode.paint(impl.r1 + 1, impl.c2 - 1, impl.r2, impl.c2, colnorm, .Vertical);
    impl.imtui.text_mode.paint(impl.r1 + 1, impl.c1 + 1, impl.r2, impl.c2 - 1, colnorm, .Blank);

    for (0..@min(impl.r2 - impl.r1 - 1, src.lines.items.len - impl.scroll_row)) |y| {
        if (impl.selection_start) |shf| if (shf.cursor_row == impl.cursor_row) {
            if (impl.scroll_row + y == impl.cursor_row) {
                if (impl.cursor_col < shf.cursor_col)
                    // within-line, to left of origin
                    // origin may be off-screen to right
                    impl.imtui.text_mode.paint(
                        y + impl.r1 + 1,
                        impl.c1 + 1 + impl.cursor_col - impl.scroll_col,
                        y + impl.r1 + 2,
                        @min(impl.c2 - 1, impl.c1 + 1 + shf.cursor_col - impl.scroll_col),
                        colnorminv,
                        .Blank,
                    )
                else
                    // within-line, on or to right of origin
                    // origin may be off-screen to left
                    impl.imtui.text_mode.paint(
                        y + impl.r1 + 1,
                        @max(impl.c1 + 1, (impl.c1 + 1 + shf.cursor_col) -| impl.scroll_col),
                        y + impl.r1 + 2,
                        impl.c1 + 1 + impl.cursor_col - impl.scroll_col,
                        colnorminv,
                        .Blank,
                    );
            }
        } else {
            if (impl.scroll_row + y >= @min(impl.cursor_row, shf.cursor_row) and
                impl.scroll_row + y <= @max(impl.cursor_row, shf.cursor_row))
            {
                impl.imtui.text_mode.paint(y + impl.r1 + 1, impl.c1 + 1, y + impl.r1 + 2, impl.c2 - 1, colnorminv, .Blank);
            }
        };
        const line = &src.lines.items[impl.scroll_row + y];
        const upper = @min(line.items.len, impl.c2 - impl.c1 - 2 + impl.scroll_col);
        if (upper > impl.scroll_col)
            impl.imtui.text_mode.write(y + impl.r1 + 1, impl.c1 + 1, line.items[impl.scroll_col..upper]);
    }

    if (active and impl.showHScrollWhenActive()) {
        impl.hscrollbar = impl.imtui.text_mode.hscrollbar(impl.r2 - 1, impl.c1 + 1, impl.c2 - 1, impl.scroll_col, MAX_LINE - (impl.c2 - impl.c1 - 3));
    }

    if (active and impl.showVScrollWhenActive()) {
        impl.vscrollbar = impl.imtui.text_mode.vscrollbar(impl.c2 - 1, impl.r1 + 1, impl.r2 - 1, impl.cursor_row, impl.source.?.lines.items.len);
    }

    if (active and impl.imtui.focus_stack.items.len == 0) { // ... XXX?
        impl.imtui.text_mode.cursor_inhibit = impl.imtui.text_mode.cursor_inhibit or (impl.r2 - impl.r1 == 1);
        impl.imtui.text_mode.cursor_row = impl.cursor_row + 1 - impl.scroll_row + impl.r1;
        impl.imtui.text_mode.cursor_col = impl.cursor_col + 1 - impl.scroll_col;
    }
}

pub fn toggledFullscreen(self: Editor) bool {
    defer self.impl.toggled_fullscreen = false;
    return self.impl.toggled_fullscreen;
}

pub fn headerDraggedTo(self: Editor) ?usize {
    defer self.impl.dragged_header_to = null;
    return self.impl.dragged_header_to;
}

pub fn isPrintableKey(keycode: SDL.Keycode) bool {
    return @intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.space) and
        @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z);
}

pub fn getCharacter(keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) u8 {
    if (@intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
        @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z))
    {
        if (modifiers.get(.left_shift) or modifiers.get(.right_shift) or modifiers.get(.caps_lock)) {
            return @as(u8, @intCast(@intFromEnum(keycode))) - ('a' - 'A');
        }
        return @intCast(@intFromEnum(keycode));
    }

    if (modifiers.get(.left_shift) or modifiers.get(.right_shift)) {
        for (ShiftTable) |e| {
            if (e.@"0" == keycode)
                return e.@"1";
        }
    }

    return @intCast(@intFromEnum(keycode));
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
