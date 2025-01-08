const std = @import("std");
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");
const TextMode = @import("../root.zig").TextMode;
const Dialog = @import("./Dialog.zig");

const DialogSelect = @This();

pub const HORIZONTAL_WIDTH = 12; // <- usable characters; 1 padding on each side added. TODO: multiple widths

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    dialog: *Dialog.Impl,

    // id
    ix: usize,

    // config
    r1: usize = undefined,
    c1: usize = undefined,
    r2: usize = undefined,
    c2: usize = undefined,
    colour: u8 = undefined,
    items: []const []const u8 = undefined,
    horizontal: bool = undefined,
    select_focus: bool = undefined,

    // state
    selected_ix: usize,
    selected_ix_focused: bool = false,
    changed: bool = false,
    scroll_dim: usize = 0,
    vscrollbar: TextMode(25, 80).Vscrollbar = .{},
    hscrollbar: TextMode(25, 80).Hscrollbar = .{},
    cmt: ?TextMode(25, 80).ScrollbarTarget = null,
    accel: ?u8 = undefined,

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .parent = parent,
                .deinit = deinit,
                .accelGet = accelGet,
                .accelerate = accelerate,
                .handleKeyPress = handleKeyPress,
                .handleKeyUp = handleKeyUp,
                .isMouseOver = isMouseOver,
                .handleMouseDown = handleMouseDown,
                .handleMouseDrag = handleMouseDrag,
                .handleMouseUp = handleMouseUp,
            },
        };
    }

    pub fn describe(self: *Impl, _: *Dialog.Impl, _: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, _: usize) void {
        self.r1 = self.dialog.r1 + r1;
        self.c1 = self.dialog.c1 + c1;
        self.r2 = self.dialog.r1 + r2;
        self.c2 = self.dialog.c1 + c2;
        self.colour = colour;
        self.items = &.{};
        self.horizontal = false;
        self.select_focus = false;
        self.accel = self.dialog.pendingAccel();

        self.imtui.text_mode.box(self.r1, self.c1, self.r2, self.c2, colour);
    }

    fn parent(ptr: *const anyopaque) ?Imtui.Control {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.dialog.control();
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.imtui.allocator.destroy(self);
    }

    fn accelGet(ptr: *const anyopaque) ?u8 {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.accel;
    }

    fn accelerate(ptr: *anyopaque) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        try self.imtui.focus(self.control());
    }

    fn setSelectedIx(self: *Impl, ix: usize) void {
        if (self.items.len == 0) {
            self.selected_ix = 0;
            return;
        }

        self.selected_ix = @min(ix, self.items.len - 1);
        self.changed = true;
        if (self.select_focus) {
            for (self.dialog.controls.items) |c|
                if (c.is(Impl)) |b| {
                    b.selected_ix_focused = false;
                };
            self.selected_ix_focused = true;
        }
    }

    pub fn value(self: *Impl, ix: usize) void {
        self.setSelectedIx(ix);

        if (self.horizontal) {
            while (ix < self.scroll_dim * (self.r2 - self.r1 - 2))
                self.scroll_dim -= 1;
            const cols = (self.c2 - self.c1 - 3) / (HORIZONTAL_WIDTH + 2);
            while (ix >= (cols + self.scroll_dim) * (self.r2 - self.r1 - 2))
                self.scroll_dim += 1;
        } else {
            if (self.scroll_dim > ix)
                self.scroll_dim = ix
            else if (ix >= self.scroll_dim + self.r2 - self.r1 - 2)
                self.scroll_dim = ix + self.r1 + 3 - self.r2;
        }
    }

    fn up(self: *Impl) void {
        if (self.select_focus and !self.selected_ix_focused)
            self.value(self.selected_ix)
        else
            self.value(self.selected_ix -| 1);
    }

    fn left(self: *Impl) void {
        self.value(self.selected_ix -| (self.r2 - self.r1 - 2));
    }

    fn right(self: *Impl) void {
        self.value(@min(self.items.len -| 1, self.selected_ix + (self.r2 - self.r1 - 2)));
    }

    fn down(self: *Impl) void {
        if (self.select_focus and !self.selected_ix_focused)
            self.value(self.selected_ix)
        else
            self.value(@min(self.items.len - 1, self.selected_ix + 1));
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        if (!self.imtui.alt_held and
            @intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
            @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z))
        {
            if (self.items.len == 0)
                return;

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
            .up => self.up(),
            .left => if (self.horizontal) self.left() else self.up(),
            .down => self.down(),
            .right => if (self.horizontal) self.right() else self.down(),
            else => try self.dialog.commonKeyPress(self.ix, keycode, modifiers),
        }
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.imtui.mouse_row >= self.r1 and self.imtui.mouse_row < self.r2 and
            self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        if (b != .left) return null;

        if (!cm) {
            if (!isMouseOver(ptr))
                return self.dialog.commonMouseDown(b, clicks, cm);
            self.cmt = null;
        }

        if (self.horizontal and (self.imtui.mouse_row == self.r2 - 1 or (cm and self.cmt != null and self.cmt.?.isHscr()))) {
            if (self.hscrollbar.hit(self.imtui.mouse_col, cm, self.cmt)) |hit| {
                const cols = (self.c2 - self.c1 - 3) / (HORIZONTAL_WIDTH + 2);
                switch (hit) {
                    .left => {
                        self.cmt = .hscr_left;
                        self.left();
                    },
                    .toward_left => {
                        self.cmt = .hscr_toward_left;
                        // Apparently equivalent to pressing left as many times
                        // as needed to move one page (i.e. cols=3 times with
                        // our current view).
                        for (0..cols) |_|
                            self.left();
                    },
                    .thumb => {
                        // Align to correct column (only).
                        const target_col = (self.hscrollbar.thumb * self.hscrollbar.highest + (self.hscrollbar.c2 - self.hscrollbar.c1 - 4)) /
                            (self.hscrollbar.c2 - self.hscrollbar.c1 - 3) * cols;
                        while (self.selected_ix / (self.r2 - self.r1 - 2) < target_col)
                            self.right();
                        while (self.selected_ix / (self.r2 - self.r1 - 2) > target_col)
                            self.left();
                    },
                    .toward_right => {
                        self.cmt = .hscr_toward_right;
                        for (0..cols) |_|
                            self.right();
                    },
                    .right => {
                        self.cmt = .hscr_right;
                        self.right();
                    },
                }
                // left/right do the selection and scrolling, thanks to
                // hscrollbars' weirdness in QB.
                return self.control();
            }
        } else if (!self.horizontal and (self.imtui.mouse_col == self.c2 - 1 or (cm and self.cmt != null and self.cmt.?.isVscr()))) {
            if (self.vscrollbar.hit(self.imtui.mouse_row, cm, self.cmt)) |hit| {
                switch (hit) {
                    .up => {
                        self.cmt = .vscr_up;
                        self.scroll_dim -|= 1;
                    },
                    .toward_up => {
                        self.cmt = .vscr_toward_up;
                        self.scroll_dim -|= self.r2 - self.r1 - 2;
                    },
                    .thumb => {
                        self.scroll_dim = (self.vscrollbar.thumb * self.vscrollbar.highest + (self.vscrollbar.r2 - self.vscrollbar.r1 - 4)) / (self.vscrollbar.r2 - self.vscrollbar.r1 - 3);
                    },
                    .toward_down => {
                        self.cmt = .vscr_toward_down;
                        self.scroll_dim = @min(self.scroll_dim + (self.r2 - self.r1 - 2), self.items.len - (self.r2 - self.r1 - 2));
                    },
                    .down => {
                        self.cmt = .vscr_down;
                        self.scroll_dim = @min(self.scroll_dim + 1, self.items.len - (self.r2 - self.r1 - 2));
                    },
                }
                if (self.selected_ix < self.scroll_dim)
                    self.setSelectedIx(self.scroll_dim)
                else if (self.selected_ix > self.scroll_dim + (self.r2 - self.r1 - 3))
                    self.setSelectedIx(self.scroll_dim + (self.r2 - self.r1 - 3));
                return self.control();
            }
        }

        try handleMouseDrag(ptr, b);

        if (self.select_focus and self.selected_ix_focused and clicks == 2) {
            if (self.dialog.default_button) |db|
                db.chosen = true;
        }

        return self.control();
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;

        if (self.cmt != null) return;

        // For default (vertical) selects:
        // - If click is on top row, or left column before the bottom row, we just
        //   shift the selection up by one, as if pressing up when focused.
        // - If click is on bottom row, or right column after the top row, we just
        //   shift the selection down by one, as if pressing down when focused.
        // - If it's elsewhere, we focus the selectbox and select the item under
        //   cursor.
        // For horizontal selects:
        // - The entire top row is up.
        // - The two non-hscrollbar cells of the bottom row are down.
        // - The non-upper/lower parts of the left and right column go left
        //   and right.
        // - Anywhere else focuses and selects.

        if (self.horizontal) {
            if (self.imtui.mouse_row <= self.r1) {
                self.up();
                return;
            }

            if (self.imtui.mouse_row >= self.r2 - 1) {
                self.down();
                return;
            }

            if (self.imtui.mouse_col <= self.c1) {
                self.left();
                return;
            }

            if (self.imtui.mouse_col >= self.c2 - 1) {
                self.right();
                return;
            }

            try self.imtui.focus(self.control());

            // can't be bothered doing arithmetic zzzzzzzzzz XXX
            var r = self.r1;
            var c = self.c1 + 1;
            const offset = self.scroll_dim * (self.r2 - self.r1 - 2);

            for (self.items[offset..], 0..) |_, ix| {
                r += 1;
                if (r == self.r2 - 1) {
                    r = self.r1 + 1;
                    c += HORIZONTAL_WIDTH + 2;
                    if (c + HORIZONTAL_WIDTH + 3 > self.c2 - 1)
                        break;
                }
                if (self.imtui.mouse_row == r and self.imtui.mouse_col >= c and self.imtui.mouse_col < c + HORIZONTAL_WIDTH + 3)
                    self.setSelectedIx(offset + ix);
            }
        } else {
            if (self.imtui.mouse_row <= self.r1 or
                (self.imtui.mouse_col == self.c1 and self.imtui.mouse_row < self.r2 - 1))
            {
                self.up();
                return;
            }

            if (self.imtui.mouse_row >= self.r2 - 1 or
                (self.imtui.mouse_col == self.c2 - 1 and self.imtui.mouse_row > self.r1))
            {
                self.down();
                return;
            }

            try self.imtui.focus(self.control());
            self.setSelectedIx(self.imtui.mouse_row - self.r1 - 1 + self.scroll_dim);
        }
    }

    fn handleMouseUp(_: *anyopaque, _: SDL.MouseButton, _: u8) !void {}
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, dialog: *Dialog.Impl, ix: usize, _: usize, _: usize, _: usize, _: usize, _: u8, _: usize) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{s}/{d}", .{ "core.DialogSelect", dialog.ident, ix });
}

pub fn create(imtui: *Imtui, dialog: *Dialog.Impl, ix: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !DialogSelect {
    var b = try imtui.allocator.create(Impl);
    b.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .dialog = dialog,
        .ix = ix,
        .selected_ix = selected,
    };
    b.describe(dialog, ix, r1, c1, r2, c2, colour, selected);
    try dialog.controls.append(imtui.allocator, b.control());
    return .{ .impl = b };
}

pub fn items(self: DialogSelect, it: []const []const u8) void {
    self.impl.items = it;
}

pub fn horizontal(self: DialogSelect) void {
    self.impl.horizontal = true;
}

pub fn select_focus(self: DialogSelect) void {
    self.impl.select_focus = true;
}

pub fn end(self: DialogSelect) void {
    const impl = self.impl;

    if (impl.horizontal) {
        {
            var r = impl.r1;
            var c = impl.c1 + 1;
            const offset = impl.scroll_dim * (impl.r2 - impl.r1 - 2);

            for (impl.items[offset..], 0..) |it, ix| {
                r += 1;
                if (r == impl.r2 - 1) {
                    r = impl.r1 + 1;
                    c += HORIZONTAL_WIDTH + 2;
                    if (c + HORIZONTAL_WIDTH + 3 > impl.c2 - 1)
                        break;
                }
                if (ix + offset == impl.selected_ix and (!impl.select_focus or impl.selected_ix_focused))
                    impl.imtui.text_mode.paint(
                        r,
                        c,
                        r + 1,
                        c + HORIZONTAL_WIDTH + 3,
                        ((impl.colour & 0x0f) << 4) | ((impl.colour & 0xf0) >> 4),
                        .Blank,
                    );
                impl.imtui.text_mode.write(r, c + 1, it[0..@min(HORIZONTAL_WIDTH, it.len)]);
            }
        }

        impl.hscrollbar = impl.imtui.text_mode.hscrollbar(
            impl.r2 - 1,
            impl.c1 + 1,
            impl.c2 - 1,
            impl.scroll_dim,
            (impl.items.len -| 1) / (impl.r2 - impl.r1 - 2),
        );

        if (impl.imtui.focused(impl.control())) {
            const r = impl.selected_ix % (impl.r2 - impl.r1 - 2);
            const c = impl.selected_ix / (impl.r2 - impl.r1 - 2);
            impl.imtui.text_mode.cursor_row = impl.r1 + 1 + r;
            impl.imtui.text_mode.cursor_col = impl.c1 + 2 + ((c - impl.scroll_dim) * (HORIZONTAL_WIDTH + 2));
        }
    } else {
        for (impl.items[impl.scroll_dim..], 0..) |it, ix| {
            const r = impl.r1 + 1 + ix;
            if (r == impl.r2 - 1) break;
            if (ix + impl.scroll_dim == impl.selected_ix and (!impl.select_focus or impl.selected_ix_focused))
                impl.imtui.text_mode.paint(
                    r,
                    impl.c1 + 1,
                    r + 1,
                    impl.c2 - 1,
                    ((impl.colour & 0x0f) << 4) | ((impl.colour & 0xf0) >> 4),
                    .Blank,
                );
            impl.imtui.text_mode.write(r, impl.c1 + 2, it[0..@min(impl.c2 - impl.c1 - 3, it.len)]);
        }

        impl.vscrollbar = impl.imtui.text_mode.vscrollbar(
            impl.c2 - 1,
            impl.r1 + 1,
            impl.r2 - 1,
            impl.scroll_dim,
            impl.items.len -| (impl.r2 - impl.r1 - 2),
        );

        if (impl.imtui.focused(impl.control())) {
            impl.imtui.text_mode.cursor_row = impl.r1 + 1 + impl.selected_ix - impl.scroll_dim;
            impl.imtui.text_mode.cursor_col = impl.c1 + 2;
        }
    }
}

pub fn changed(self: DialogSelect) ?usize {
    defer self.impl.changed = false;
    return if (self.impl.changed) self.impl.selected_ix else null;
}
