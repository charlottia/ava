const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Editor = @This();

top: usize,
height: usize,
fullscreened: ?struct {
    old_top: usize,
    old_height: usize,
} = null,

const MAX_LINE = 255;

pub fn toggleFullscreen(self: *Editor) void {
    if (self.fullscreened) |pre| {
        self.top = pre.old_top;
        self.height = pre.old_height;
        self.fullscreened = null;
    } else {
        self.fullscreened = .{
            .old_top = self.top,
            .old_height = self.height,
        };
        self.top = 1;
        self.height = 22;
    }
}

pub fn handleMouseDown(self: *Editor, active: bool, button: SDL.MouseButton, clicks: u8, x: usize, y: usize) bool {
    _ = button;
    _ = clicks;

    if (y == self.top)
        return true;

    if (y > self.top and y <= self.top + self.height and x > 0 and x < 79) {
        const scrollbar = self.kind != .immediate and y == self.top + self.height;
        if (scrollbar and active) {
            if (x == 1) {
                if (self.scroll_col > 0) {
                    self.scroll_col -= 1;
                    self.cursor_col -= 1;
                }
            } else if (x > 1 and x < 78) {
                const hst = self.horizontalScrollThumb();
                if (x - 2 < hst)
                    self.scroll_col = if (self.scroll_col >= 78) self.scroll_col - 78 else 0
                else if (x - 2 > hst)
                    self.scroll_col = if (self.scroll_col <= MAX_LINE - 77 - 78) self.scroll_col + 78 else MAX_LINE - 77
                else
                    self.scroll_col = (hst * (MAX_LINE - 77) + 74) / 75;
                self.cursor_col = self.scroll_col;
            } else if (x == 78) {
                if (self.scroll_col < (MAX_LINE - 77)) {
                    self.scroll_col += 1;
                    self.cursor_col += 1;
                }
            }
            if (self.cursor_col < self.scroll_col)
                self.cursor_col = self.scroll_col
            else if (self.cursor_col > self.scroll_col + 77)
                self.cursor_col = self.scroll_col + 77;
        } else {
            const eff_y = if (scrollbar) y - 1 else y;
            self.cursor_col = self.scroll_col + x - 1;
            self.cursor_row = @min(self.scroll_row + eff_y - self.top - 1, self.lines.items.len);
        }
        return true;
    }

    if (active and self.kind != .immediate and y > self.top and y < self.top + self.height and x == 79) {
        if (y == self.top + 1) {
            std.debug.print("^\n", .{});
        } else if (y > self.top + 1 and y < self.top + self.height - 1) {
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
            if (y - self.top - 2 < vst)
                self.pageUp()
            else if (y - self.top - 2 > vst)
                self.pageDown()
            else {
                // TODO: the thing, zhu li
            }
        } else if (y == self.top + self.height - 1) {
            std.debug.print("v\n", .{});
        }
        return true;
    }

    return false;
}

pub fn handleMouseUp(self: *Editor, button: SDL.MouseButton, clicks: u8, x: usize, y: usize) void {
    _ = button;

    if (y == self.top) {
        if ((self.kind != .immediate and x == 76) or clicks == 2)
            self.toggleFullscreen();
        return;
    }
}

pub fn pageUp(self: *Editor) void {
    _ = self;
    // self.scroll_y = if (self.scroll_y >=
    // std.debug.print("pgup\n", .{})
}

pub fn pageDown(self: *Editor) void {
    _ = self;
    // self.scroll_y = if (self.scroll_y >=
    // std.debug.print("pgup\n", .{})
}
