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

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .parent = parent,
                .deinit = deinit,
                .generationGet = generationGet,
                .generationSet = generationSet,
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
        self.accel = null;

        self.dialog.imtui.text_mode.box(self.r1, self.c1, self.r2, self.c2, colour);

        if (self.imtui.focused(self.control())) {
            self.dialog.imtui.text_mode.cursor_row = self.r1 + 1 + self.selected_ix - self.scroll_row;
            self.dialog.imtui.text_mode.cursor_col = self.c1 + 2;
        }
    }

    fn parent(ptr: *const anyopaque) ?Imtui.Control {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.dialog.control();
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.imtui.allocator.destroy(self);
    }

    fn generationGet(ptr: *const anyopaque) usize {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.generation;
    }

    fn generationSet(ptr: *anyopaque, n: usize) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.generation = n;
    }

    fn accelGet(ptr: *const anyopaque) ?u8 {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.accel;
    }

    fn accelerate(ptr: *anyopaque) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        try self.imtui.focus(self.control());
    }

    pub fn value(self: *Impl, ix: usize) void {
        self.selected_ix = ix;
        if (self.scroll_row > ix)
            self.scroll_row = ix
        else if (ix >= self.scroll_row + self.r2 - self.r1 - 2)
            self.scroll_row = ix + self.r1 + 3 - self.r2;
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
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

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.dialog.imtui.mouse_row >= self.r1 and self.dialog.imtui.mouse_row < self.r2 and
            self.dialog.imtui.mouse_col >= self.c1 and self.dialog.imtui.mouse_col < self.c2;
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        if (b != .left) return null;

        if (!cm) {
            if (!isMouseOver(ptr))
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
                return self.control();
            }
        }

        try handleMouseDrag(ptr, b);
        return self.control();
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
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

        try self.imtui.focus(self.control());
        self.selected_ix = self.dialog.imtui.mouse_row - self.r1 - 1 + self.scroll_row;
    }

    fn handleMouseUp(_: *anyopaque, _: SDL.MouseButton, _: u8) !void {}
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, dialog: *Dialog.Impl, ix: usize, _: usize, _: usize, _: usize, _: usize, _: u8, _: usize) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{s}/{d}", .{ "core.DialogSelect", dialog.title, ix });
}

pub fn create(imtui: *Imtui, dialog: *Dialog.Impl, ix: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !DialogSelect {
    var b = try imtui.allocator.create(Impl);
    b.* = .{
        .imtui = imtui,
        .dialog = dialog,
        .generation = imtui.generation,
        .ix = ix,
        .selected_ix = selected,
    };
    b.describe(dialog, ix, r1, c1, r2, c2, colour, selected);
    try dialog.controls.append(imtui.allocator, b.control());
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
