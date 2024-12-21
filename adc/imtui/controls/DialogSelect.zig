const std = @import("std");
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");
const TextMode = @import("../root.zig").TextMode;
const Dialog = @import("./Dialog.zig");

const DialogSelect = @This();

pub const Impl = struct {
    imtui: *Imtui,
    dialog: *Dialog.Impl,
    generation: usize,

    // id
    ix: usize,

    // config
    r1: usize = undefined,
    c1: usize = undefined,
    r2: usize = undefined,
    c2: usize = undefined,
    colour: u8 = undefined,
    items: []const []const u8 = undefined,
    accel: ?u8 = undefined,

    // state
    selected_ix: usize,
    scroll_row: usize = 0,
    vscrollbar: TextMode(25, 80).Vscrollbar = .{},
    cmt: ?TextMode(25, 80).ScrollbarTarget = null,

    pub fn deinit(self: *Impl) void {
        self.imtui.allocator.destroy(self);
    }

    pub fn parent(self: *const Impl) Imtui.Control {
        return .{ .dialog = self.dialog };
    }

    pub fn describe(self: *Impl, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
        self.r1 = self.dialog.r1 + r1;
        self.c1 = self.dialog.c1 + c1;
        self.r2 = self.dialog.r1 + r2;
        self.c2 = self.dialog.c1 + c2;
        self.colour = colour;
        self.items = &.{};
        self.accel = null;

        self.dialog.imtui.text_mode.box(self.r1, self.c1, self.r2, self.c2, colour);

        if (self.imtui.focused(self)) {
            self.dialog.imtui.text_mode.cursor_row = self.r1 + 1 + self.selected_ix - self.scroll_row;
            self.dialog.imtui.text_mode.cursor_col = self.c1 + 2;
        }
    }

    pub fn accelerate(self: *Impl) !void {
        try self.imtui.focus(self);
    }

    pub fn value(self: *Impl, ix: usize) void {
        self.selected_ix = ix;
        if (self.scroll_row > ix)
            self.scroll_row = ix
        else if (ix >= self.scroll_row + self.r2 - self.r1 - 2)
            self.scroll_row = ix + self.r1 + 3 - self.r2;
    }

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        if (!self.imtui.alt_held and
            @intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
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

        switch (keycode) {
            .up, .left => self.value(self.selected_ix -| 1),
            .down, .right => self.value(@min(self.items.len - 1, self.selected_ix + 1)),
            else => try self.dialog.commonKeyPress(self.ix, keycode, modifiers),
        }
    }

    pub fn isMouseOver(self: *const Impl) bool {
        return self.dialog.imtui.mouse_row >= self.r1 and self.dialog.imtui.mouse_row < self.r2 and
            self.dialog.imtui.mouse_col >= self.c1 and self.dialog.imtui.mouse_col < self.c2;
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        if (b != .left) return null;

        if (!cm) {
            if (!self.isMouseOver())
                return self.dialog.commonMouseDown(b, clicks, cm);
            self.cmt = null;
        }

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
                return .{ .dialog_select = self };
            }
        }

        try self.handleMouseDrag(b);
        return .{ .dialog_select = self };
    }

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        _ = b;

        if (self.cmt != null) return;

        // - If click is on top row, or left column before the bottom row, we just
        //   shift the selection up by one, as if pressing up() when focused.
        // - If click is on bottom row, or right column after the top row, we just
        //   shift the selection down by one, as if pressing down() when focused.
        // - If it's elsewhere, we focus the selectbox and select the item under
        //   cursor.
        if (self.dialog.imtui.mouse_row <= self.r1 or
            (self.dialog.imtui.mouse_col == self.c1 and self.dialog.imtui.mouse_row < self.r2 - 1))
        {
            self.value(self.selected_ix -| 1);
            return;
        }

        if (self.dialog.imtui.mouse_row >= self.r2 - 1 or
            (self.dialog.imtui.mouse_col == self.c2 - 1 and self.dialog.imtui.mouse_row > self.r1))
        {
            self.value(@min(self.items.len - 1, self.selected_ix + 1));
            return;
        }

        try self.imtui.focus(self);
        self.selected_ix = self.dialog.imtui.mouse_row - self.r1 - 1 + self.scroll_row;
    }
};

impl: *Impl,

pub fn create(dialog: *Dialog.Impl, ix: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !DialogSelect {
    var b = try dialog.imtui.allocator.create(Impl);
    b.* = .{
        .imtui = dialog.imtui,
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        .ix = ix,
        .selected_ix = selected,
    };
    b.describe(r1, c1, r2, c2, colour);
    return .{ .impl = b };
}

pub fn accel(self: DialogSelect, key: u8) void {
    self.impl.accel = key;
}

pub fn items(self: DialogSelect, it: []const []const u8) void {
    self.impl.items = it;
}

pub fn end(self: DialogSelect) void {
    for (self.impl.items[self.impl.scroll_row..], 0..) |it, ix| {
        const r = self.impl.r1 + 1 + ix;
        if (r == self.impl.r2 - 1) break;
        if (ix + self.impl.scroll_row == self.impl.selected_ix)
            self.impl.dialog.imtui.text_mode.paint(
                r,
                self.impl.c1 + 1,
                r + 1,
                self.impl.c2 - 1,
                ((self.impl.colour & 0x0f) << 4) | ((self.impl.colour & 0xf0) >> 4),
                .Blank,
            );
        self.impl.dialog.imtui.text_mode.write(
            r,
            self.impl.c1 + 2,
            it,
        );
    }

    self.impl.vscrollbar = self.impl.dialog.imtui.text_mode.vscrollbar(
        self.impl.c2 - 1,
        self.impl.r1 + 1,
        self.impl.r2 - 1,
        self.impl.scroll_row,
        self.impl.items.len -| (self.impl.r2 - self.impl.r1 - 2),
    );
}
