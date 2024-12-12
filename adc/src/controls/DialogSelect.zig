const std = @import("std");
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");
const Dialog = @import("./Dialog.zig");

const DialogSelect = @This();

pub const Impl = struct {
    dialog: *Dialog.Impl,
    ix: usize = undefined,
    generation: usize,
    r1: usize = undefined,
    c1: usize = undefined,
    r2: usize = undefined,
    c2: usize = undefined,
    colour: u8 = undefined,
    items: []const []const u8 = undefined,
    accel: ?u8 = undefined,
    selected_ix: usize,
    scroll_row: usize = 0,
    vscrollbar: Imtui.TextMode.Vscrollbar = .{},
    cmt: ?Imtui.TextMode.ScrollbarTarget = null,

    pub fn deinit(self: *Impl) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, ix: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
        self.ix = ix;
        self.r1 = self.dialog.imtui.text_mode.offset_row + r1;
        self.c1 = self.dialog.imtui.text_mode.offset_col + c1;
        self.r2 = self.dialog.imtui.text_mode.offset_row + r2;
        self.c2 = self.dialog.imtui.text_mode.offset_col + c2;
        self.colour = colour;
        self.items = &.{};
        self.accel = null;

        self.dialog.imtui.text_mode.box(r1, c1, r2, c2, colour);

        if (self.dialog.focus_ix == ix) {
            self.dialog.imtui.text_mode.cursor_row = self.r1 + 1 + self.selected_ix - self.scroll_row;
            self.dialog.imtui.text_mode.cursor_col = self.c1 + 2;
        }
    }

    pub fn accelerate(self: *Impl) void {
        self.dialog.focus_ix = self.ix;
    }

    pub fn value(self: *Impl, ix: usize) void {
        self.selected_ix = ix;
        if (self.scroll_row > ix)
            self.scroll_row = ix
        else if (ix >= self.scroll_row + self.r2 - self.r1 - 2)
            self.scroll_row = ix + self.r1 + 3 - self.r2;
    }

    pub fn up(self: *Impl) void {
        self.value(self.selected_ix -| 1);
    }

    pub fn down(self: *Impl) void {
        self.value(@min(self.items.len - 1, self.selected_ix + 1));
    }

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        _ = modifiers;

        if (@intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
            @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z))
        {
            // advance to next item starting with pressed key (if any)
            var next = (self.selected_ix + 1) % self.items.len;
            while (next != self.selected_ix) : (next = (next + 1) % self.items.len) {
                // SDLK_a..SDLK_z correspond to 'a'..'z' in ASCII.
                if (std.ascii.toLower(self.items[next][0]) == @intFromEnum(keycode)) {
                    self.value(next);
                    return;
                }
            }
            return;
        }
    }

    pub fn mouseIsOver(self: *const Impl) bool {
        return self.dialog.imtui.mouse_row >= self.r1 and self.dialog.imtui.mouse_row < self.r2 and
            self.dialog.imtui.mouse_col >= self.c1 and self.dialog.imtui.mouse_col < self.c2;
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !void {
        _ = clicks;

        if (b != .left) return;

        if (!cm)
            self.cmt = null;

        if (self.dialog.imtui.mouse_col == self.c2 - 1 or (cm and self.cmt != null and self.cmt.?.isVscr())) {
            if (self.vscrollbar.hit(self.dialog.imtui.mouse_row, cm, self.cmt)) |hit| {
                switch (hit) {
                    .up => {
                        self.cmt = .vscr_up;
                        self.scroll_row -|= 1;
                    },
                    .toward_up => {
                        self.cmt = .vscr_toward_up;
                        self.scroll_row -|= self.r2 - self.r1 - 2;
                    },
                    .thumb => {
                        self.scroll_row = (self.vscrollbar.thumb * self.vscrollbar.highest + (self.vscrollbar.r2 - self.vscrollbar.r1 - 4)) / (self.vscrollbar.r2 - self.vscrollbar.r1 - 3);
                    },
                    .toward_down => {
                        self.cmt = .vscr_toward_down;
                        self.scroll_row = @min(self.scroll_row + (self.r2 - self.r1 - 2), self.items.len - (self.r2 - self.r1 - 2));
                    },
                    .down => {
                        self.cmt = .vscr_down;
                        self.scroll_row = @min(self.scroll_row + 1, self.items.len - (self.r2 - self.r1 - 2));
                    },
                }
                if (self.selected_ix < self.scroll_row)
                    self.selected_ix = self.scroll_row
                else if (self.selected_ix > self.scroll_row + (self.r2 - self.r1 - 3))
                    self.selected_ix = self.scroll_row + (self.r2 - self.r1 - 3);
                return;
            }
        }

        return self.handleMouseDrag(b);
    }

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        if (b != .left) return;
        if (self.cmt != null) return;

        // - If click is on top row, or left column before the bottom row, we just
        //   shift the selection up by one, as if pressing up() when focussed.
        // - If click is on bottom row, or right column after the top row, we just
        //   shift the selection down by one, as if pressing down() when focussed.
        // - If it's elsewhere, we focus the selectbox and select the item under
        //   cursor.
        if (self.dialog.imtui.mouse_row <= self.r1 or
            (self.dialog.imtui.mouse_col == self.c1 and self.dialog.imtui.mouse_row < self.r2 - 1))
        {
            self.up();
            return;
        }

        if (self.dialog.imtui.mouse_row >= self.r2 - 1 or
            (self.dialog.imtui.mouse_col == self.c2 - 1 and self.dialog.imtui.mouse_row > self.r1))
        {
            self.down();
            return;
        }

        self.dialog.focus_ix = self.ix;
        self.selected_ix = self.dialog.imtui.mouse_row - self.r1 - 1 + self.scroll_row;
    }
};

impl: *Impl,

pub fn create(dialog: *Dialog.Impl, ix: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !DialogSelect {
    var b = try dialog.imtui.allocator.create(Impl);
    b.* = .{
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        .selected_ix = selected,
    };
    b.describe(ix, r1, c1, r2, c2, colour);
    return .{ .impl = b };
}

pub fn accel(self: DialogSelect, key: u8) void {
    self.impl.accel = key;
}

pub fn items(self: DialogSelect, it: []const []const u8) void {
    self.impl.items = it;
}

pub fn end(self: DialogSelect) void {
    // XXX: the offset stuff got real ugly here.

    for (self.impl.items[self.impl.scroll_row..], 0..) |it, ix| {
        const r = self.impl.r1 + 1 + ix;
        if (r == self.impl.r2 - 1) break;
        if (ix + self.impl.scroll_row == self.impl.selected_ix)
            self.impl.dialog.imtui.text_mode.paint(
                r - self.impl.dialog.imtui.text_mode.offset_row,
                self.impl.c1 + 1 - self.impl.dialog.imtui.text_mode.offset_col,
                r + 1 - self.impl.dialog.imtui.text_mode.offset_row,
                self.impl.c2 - 1 - self.impl.dialog.imtui.text_mode.offset_col,
                ((self.impl.colour & 0x0f) << 4) | ((self.impl.colour & 0xf0) >> 4),
                .Blank,
            );
        self.impl.dialog.imtui.text_mode.write(
            r - self.impl.dialog.imtui.text_mode.offset_row,
            self.impl.c1 + 2 - self.impl.dialog.imtui.text_mode.offset_col,
            it,
        );
    }

    self.impl.vscrollbar = self.impl.dialog.imtui.text_mode.vscrollbar(
        self.impl.c2 - 1 - self.impl.dialog.imtui.text_mode.offset_col,
        self.impl.r1 + 1 - self.impl.dialog.imtui.text_mode.offset_row,
        self.impl.r2 - 1 - self.impl.dialog.imtui.text_mode.offset_row,
        self.impl.scroll_row,
        self.impl.items.len -| (self.impl.r2 - self.impl.r1 - 2),
    );
}
