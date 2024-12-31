const std = @import("std");
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

// A fair bit of the below can be further simplified if we change all self.
// [rc][12] to be in absolute coordinates; at the moment everything is Dialog
// relative, except of course Dialog itself.
//     An alternative solution would be for controls to declare whether they're
// Dialog-offset or not.
//     Ideally behaviours could be freely composable in a somewhat automated
// way. For now this keeps the repetition in one place.

fn corners(r1: usize, c1: usize, r2: usize, c2: usize) [4]struct { r: usize, c: usize } {
    return .{
        .{ .r = r1, .c = c1 },
        .{ .r = r1, .c = c2 - 1 },
        .{ .r = r2 - 1, .c = c1 },
        .{ .r = r2 - 1, .c = c2 - 1 },
    };
}

pub fn describe_whResizable(self: anytype, r1: usize, c1: usize, r2: usize, c2: usize) bool {
    const c = self.control();

    if (!self.imtui.focused(c)) {
        if (self.imtui.focus_stack.items.len > 1 and !self.root.focus_idle)
            return true;

        if (c.isMouseOver() and !(self.root.focus_idle and self.imtui.focus_stack.getLast().isMouseOver()))
            self.imtui.text_mode.paintColour(r1 - 1, c1 - 1, r2 + 1, c2 + 1, 0x20, .outline);
        return true;
    } else switch (self.state) {
        .idle => {
            for (corners(r1, c1, r2, c2)) |corner|
                if (self.imtui.text_mode.mouse_row == corner.r and self.imtui.text_mode.mouse_col == corner.c) {
                    self.imtui.text_mode.paintColour(corner.r - 1, corner.c - 1, corner.r + 2, corner.c + 2, 0xd0, .outline);
                    return true;
                };

            if (self.imtui.text_mode.mouse_row == r1 and
                self.imtui.text_mode.mouse_col >= self.text_start - 1 and
                self.imtui.text_mode.mouse_col < self.text_start + self.text.items.len + 1)
            {
                self.imtui.text_mode.paintColour(r1, self.text_start - 1, r1 + 1, self.text_start + self.text.items.len + 1, 0xd0, .fill);
                return true;
            }

            const border_colour: u8 = if (c.isMouseOver()) 0xd0 else 0x50;
            self.imtui.text_mode.paintColour(r1 - 1, c1 - 1, r2 + 1, c2 + 1, border_colour, .outline);
            return true;
        },
        .move, .resize => return true,
        else => return false,
    }
}

pub fn describe_widthResizable(self: anytype) void {
    const c = self.control();

    if (!self.imtui.focused(c)) {
        if (self.imtui.focus_stack.items.len > 1 and !self.root.focus_idle)
            return;

        if (c.isMouseOver() and !(self.root.focus_idle and self.imtui.focus_stack.getLast().isMouseOver()))
            self.imtui.text_mode.paintColour(self.dialog.r1 + self.r1, self.dialog.c1 + self.c1, self.dialog.r1 + self.r2, self.dialog.c1 + self.c2, 0x20, .fill);
    } else switch (self.state) {
        .idle => {
            if (self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c1) {
                self.imtui.text_mode.paintColour(self.dialog.r1 + self.r1 - 1, self.dialog.c1 + self.c1 - 1, self.dialog.r1 + self.r1 + 2, self.dialog.c1 + self.c1 + 2, 0xd0, .outline);
                return;
            }

            if (self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c2 - 1) {
                self.imtui.text_mode.paintColour(self.dialog.r1 + self.r1 - 1, self.dialog.c1 + self.c2 - 2, self.dialog.r1 + self.r1 + 2, self.dialog.c1 + self.c2 + 1, 0xd0, .outline);
                return;
            }

            const border_colour: u8 = if (c.isMouseOver()) 0xd0 else 0x50;
            self.imtui.text_mode.paintColour(self.dialog.r1 + self.r1, self.dialog.c1 + self.c1, self.dialog.r1 + self.r2, self.dialog.c1 + self.c2, border_colour, .fill);
        },
        .move, .resize => {},
    }
}

pub fn describe_autosized(self: anytype) bool {
    const c = self.control();

    if (!self.imtui.focused(self.control())) {
        if (self.imtui.focus_stack.items.len > 1 and !self.root.focus_idle)
            return true;

        if (c.isMouseOver() and !(self.root.focus_idle and self.imtui.focus_stack.getLast().isMouseOver()))
            self.imtui.text_mode.paintColour(self.dialog.r1 + self.r1, self.dialog.c1 + self.c1, self.dialog.r1 + self.r2, self.dialog.c1 + self.c2, 0x20, .fill);
        return true;
    } else switch (self.state) {
        .idle => {
            const border_colour: u8 = if (c.isMouseOver()) 0xd0 else 0x50;
            self.imtui.text_mode.paintColour(self.dialog.r1 + self.r1, self.dialog.c1 + self.c1, self.dialog.r1 + self.r2, self.dialog.c1 + self.c2, border_colour, .fill);
            return true;
        },
        .move => return true,
        else => return false,
    }
}

pub fn isMouseOver_whResizable(self: anytype, r1: usize, c1: usize, r2: usize, c2: usize) bool {
    return self.state == .text_edit or
        (self.imtui.mouse_row >= r1 and self.imtui.mouse_row < r2 and
        self.imtui.mouse_col >= c1 and self.imtui.mouse_col < c2 and
        (self.imtui.text_mode.mouse_row == r1 or self.imtui.text_mode.mouse_row == r2 - 1 or
        self.imtui.text_mode.mouse_col == c1 or self.imtui.text_mode.mouse_col == c2 - 1));
}

pub fn isMouseOver_widthResizable(self: anytype) bool {
    return self.imtui.mouse_row >= self.dialog.r1 + self.r1 and
        self.imtui.mouse_row < self.dialog.r1 + self.r2 and
        self.imtui.mouse_col >= self.dialog.c1 + self.c1 and
        self.imtui.mouse_col < self.dialog.c1 + self.c2;
}

pub fn isMouseOver_autosized(self: anytype) bool {
    return self.state == .text_edit or
        (self.imtui.mouse_row >= self.dialog.r1 + self.r1 and
        self.imtui.mouse_row < self.dialog.r1 + self.r2 and
        self.imtui.mouse_col >= self.dialog.c1 + self.c1 and
        self.imtui.mouse_col < self.dialog.c1 + self.c2);
}

pub fn handleMouseDown_whResizable(self: anytype, b: SDL.MouseButton, clicks: u8, cm: bool, r1: usize, c1: usize, r2: usize, c2: usize) !?Imtui.Control {
    const c = self.control();

    if (cm) return null;

    const focused = self.imtui.focused(c);
    if (!c.isMouseOver())
        if (try self.imtui.fallbackMouseDown(b, clicks, cm)) |r|
            return r.@"0"
        else {
            if (focused) self.imtui.unfocusAnywhere(c);
            return null;
        };

    if (b != .left) return null;

    if (!focused) {
        self.state = .{ .move = .{
            .origin_row = self.imtui.text_mode.mouse_row,
            .origin_col = self.imtui.text_mode.mouse_col,
            .edit_eligible = false,
        } };
        try self.imtui.focus(c);
        return c;
    } else switch (self.state) {
        .idle => {
            for (corners(r1, c1, r2, c2), 0..) |corner, cix|
                if (self.imtui.text_mode.mouse_row == corner.r and
                    self.imtui.text_mode.mouse_col == corner.c)
                {
                    self.state = .{ .resize = .{ .cix = cix } };
                    return c;
                };

            const edit_eligible = self.imtui.text_mode.mouse_row == r1 and
                self.imtui.text_mode.mouse_col >= self.text_start - 1 and
                self.imtui.text_mode.mouse_col < self.text_start + self.text.items.len + 1;

            self.state = .{ .move = .{
                .origin_row = self.imtui.text_mode.mouse_row,
                .origin_col = self.imtui.text_mode.mouse_col,
                .edit_eligible = edit_eligible,
            } };
            return c;
        },
        .text_edit => {
            if (!(self.imtui.text_mode.mouse_row == r1 and
                self.imtui.text_mode.mouse_col >= self.text_start - 1 and
                self.imtui.text_mode.mouse_col < self.text_start + self.text.items.len + 1))
            {
                self.state = .idle;
            }

            return null;
        },
        else => return null,
    }
}

pub fn handleMouseDown_widthResizable(self: anytype, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
    const c = self.control();

    if (cm) return null;

    const focused = self.imtui.focused(c);
    if (!c.isMouseOver())
        if (try self.imtui.fallbackMouseDown(b, clicks, cm)) |r|
            return r.@"0"
        else {
            if (focused) self.imtui.unfocusAnywhere(c);
            return null;
        };

    if (b != .left) return null;

    if (!focused) {
        self.state = .{ .move = .{
            .origin_row = self.imtui.text_mode.mouse_row,
            .origin_col = self.imtui.text_mode.mouse_col,
        } };
        try self.imtui.focus(c);
        return c;
    } else switch (self.state) {
        .idle => {
            if (self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c1) {
                self.state = .{ .resize = .{ .end = 0 } };
                return c;
            }

            if (self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c2 - 1) {
                self.state = .{ .resize = .{ .end = 1 } };
                return c;
            }

            self.state = .{ .move = .{
                .origin_row = self.imtui.text_mode.mouse_row,
                .origin_col = self.imtui.text_mode.mouse_col,
            } };
            return c;
        },
        else => return null,
    }
}

pub fn handleMouseDown_autosized(self: anytype, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
    const c = self.control();

    if (cm) return null;

    const focused = self.imtui.focused(c);
    if (!c.isMouseOver())
        if (try self.imtui.fallbackMouseDown(b, clicks, cm)) |r|
            return r.@"0"
        else {
            if (focused) self.imtui.unfocusAnywhere(c);
            return null;
        };

    if (b != .left) return null;

    if (!focused) {
        self.state = .{ .move = .{
            .origin_row = self.imtui.text_mode.mouse_row,
            .origin_col = self.imtui.text_mode.mouse_col,
            .edit_eligible = false,
        } };
        try self.imtui.focus(c);
        return c;
    } else switch (self.state) {
        .idle => {
            self.state = .{ .move = .{
                .origin_row = self.imtui.text_mode.mouse_row,
                .origin_col = self.imtui.text_mode.mouse_col,
                .edit_eligible = true,
            } };
            return self.control();
        },
        .text_edit => {
            if (!(self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and
                self.imtui.text_mode.mouse_col >= self.dialog.c1 + self.c1 and
                self.imtui.text_mode.mouse_col < self.dialog.c1 + self.c2))
            {
                self.state = .idle;
            }

            return null;
        },
        else => return null,
    }
}

pub fn handleMouseDrag_whResizable(self: anytype, b: SDL.MouseButton, r_adjust: usize, c_adjust: usize) !void {
    _ = b;

    switch (self.state) {
        .move => |*d| {
            const dr = @as(isize, @intCast(self.imtui.text_mode.mouse_row)) - @as(isize, @intCast(d.origin_row));
            const dc = @as(isize, @intCast(self.imtui.text_mode.mouse_col)) - @as(isize, @intCast(d.origin_col));
            if (self.adjustRow(dr)) {
                d.origin_row = @intCast(@as(isize, @intCast(d.origin_row)) + dr);
                d.edit_eligible = false;
            }
            if (self.adjustCol(dc)) {
                d.origin_col = @intCast(@as(isize, @intCast(d.origin_col)) + dc);
                d.edit_eligible = false;
            }
        },
        .resize => |d| {
            switch (d.cix) {
                0, 1 => self.r1 = self.imtui.text_mode.mouse_row - r_adjust,
                2, 3 => self.r2 = self.imtui.text_mode.mouse_row + 1 - r_adjust,
                else => unreachable,
            }
            switch (d.cix) {
                0, 2 => self.c1 = self.imtui.text_mode.mouse_col - c_adjust,
                1, 3 => self.c2 = self.imtui.text_mode.mouse_col + 1 - c_adjust,
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

pub fn handleMouseDrag_widthResizable(self: anytype, b: SDL.MouseButton) !void {
    _ = b;

    switch (self.state) {
        .move => |*d| {
            const dr = @as(isize, @intCast(self.imtui.text_mode.mouse_row)) - @as(isize, @intCast(d.origin_row));
            const dc = @as(isize, @intCast(self.imtui.text_mode.mouse_col)) - @as(isize, @intCast(d.origin_col));
            if (self.adjustRow(dr))
                d.origin_row = @intCast(@as(isize, @intCast(d.origin_row)) + dr);
            if (self.adjustCol(dc))
                d.origin_col = @intCast(@as(isize, @intCast(d.origin_col)) + dc);
        },
        .resize => |d| {
            switch (d.end) {
                0 => self.c1 = self.imtui.text_mode.mouse_col -| self.dialog.c1,
                1 => self.c2 = @min(self.imtui.text_mode.mouse_col -| self.dialog.c1 + 1, self.dialog.c2 - self.dialog.c1),
            }
        },
        else => unreachable,
    }
}

pub fn handleMouseDrag_autosized(self: anytype, b: SDL.MouseButton) !void {
    _ = b;

    switch (self.state) {
        .move => |*d| {
            const dr = @as(isize, @intCast(self.imtui.text_mode.mouse_row)) - @as(isize, @intCast(d.origin_row));
            const dc = @as(isize, @intCast(self.imtui.text_mode.mouse_col)) - @as(isize, @intCast(d.origin_col));
            if (self.adjustRow(dr)) {
                d.origin_row = @intCast(@as(isize, @intCast(d.origin_row)) + dr);
                d.edit_eligible = false;
            }
            if (self.adjustCol(dc)) {
                d.origin_col = @intCast(@as(isize, @intCast(d.origin_col)) + dc);
                d.edit_eligible = false;
            }
        },
        else => unreachable,
    }
}

pub fn handleMouseUp_whResizable(self: anytype, b: SDL.MouseButton, clicks: u8) !void {
    _ = b;
    _ = clicks;
    switch (self.state) {
        .move => |d| {
            self.state = .idle;
            if (d.edit_eligible)
                try startTextEdit(self);
        },
        .resize => self.state = .idle,
        else => unreachable,
    }
}

pub fn handleMouseUp_widthResizable(self: anytype, b: SDL.MouseButton, clicks: u8) !void {
    _ = b;
    _ = clicks;

    switch (self.state) {
        .move, .resize => self.state = .idle,
        else => unreachable,
    }
}

pub fn handleMouseUp_autosized(self: anytype, b: SDL.MouseButton, clicks: u8) !void {
    _ = b;
    _ = clicks;

    switch (self.state) {
        .move => |d| {
            self.state = .idle;
            if (d.edit_eligible)
                try startTextEdit(self);
        },
        else => unreachable,
    }
}

pub fn handleKeyPress_whResizable(self: anytype, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !bool {
    switch (self.state) {
        .idle => {
            switch (keycode) {
                .up => if (modifiers.get(.left_shift) or modifiers.get(.right_shift)) {
                    self.r2 -|= 1;
                } else {
                    _ = self.adjustRow(-1);
                },
                .down => if (modifiers.get(.left_shift) or modifiers.get(.right_shift)) {
                    self.r2 += 1;
                } else {
                    _ = self.adjustRow(1);
                },
                .left => if (modifiers.get(.left_shift) or modifiers.get(.right_shift)) {
                    self.c2 -|= 1;
                } else {
                    _ = self.adjustCol(-1);
                },
                .right => if (modifiers.get(.left_shift) or modifiers.get(.right_shift)) {
                    self.c2 += 1;
                } else {
                    _ = self.adjustCol(1);
                },
                else => try self.imtui.fallbackKeyPress(keycode, modifiers),
            }
            return true;
        },
        .move, .resize => return true,
        else => return false,
    }
}

pub fn handleKeyPress_widthResizable(self: anytype, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    switch (self.state) {
        .idle => switch (keycode) {
            .up => _ = self.adjustRow(-1),
            .down => _ = self.adjustRow(1),
            .left => if (modifiers.get(.left_shift) or modifiers.get(.right_shift)) {
                self.c2 -|= 1;
            } else {
                _ = self.adjustCol(-1);
            },
            .right => if (modifiers.get(.left_shift) or modifiers.get(.right_shift)) {
                self.c2 = @min(self.c2 + 1, self.dialog.c2 - self.dialog.c1);
            } else {
                _ = self.adjustCol(1);
            },
            else => return self.imtui.fallbackKeyPress(keycode, modifiers),
        },
        .move, .resize => {},
    }
}

pub fn handleKeyPress_autosized(self: anytype, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !bool {
    switch (self.state) {
        .idle => {
            switch (keycode) {
                .up => _ = self.adjustRow(-1),
                .down => _ = self.adjustRow(1),
                .left => _ = self.adjustCol(-1),
                .right => _ = self.adjustCol(1),
                else => try self.imtui.fallbackKeyPress(keycode, modifiers),
            }
            return true;
        },
        .move => return true,
        else => return false,
    }
}

pub fn handleKeyPress_textEdit(self: anytype, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    switch (keycode) {
        .backspace => if (self.text.items.len > 0) {
            if (modifiers.get(.left_control) or modifiers.get(.right_control))
                self.text.items.len = 0
            else
                self.text.items.len -= 1;
        },
        .@"return" => self.state = .idle,
        .escape => {
            self.state = .idle;
            try self.text.replaceRange(self.imtui.allocator, 0, self.text.items.len, self.text_orig.items);
        },
        else => if (Imtui.Controls.isPrintableKey(keycode)) {
            try self.text.append(self.imtui.allocator, Imtui.Controls.getCharacter(keycode, modifiers));
        },
    }
}

pub fn adjustRow(self: anytype, lb: usize, ub: usize, dr: isize) bool {
    const r1: isize = @as(isize, @intCast(self.r1)) + dr;
    const r2: isize = @as(isize, @intCast(self.r2)) + dr;
    if (r1 >= lb and r2 <= ub) {
        self.r1 = @intCast(r1);
        self.r2 = @intCast(r2);
        return true;
    }
    return false;
}

pub fn adjustCol(self: anytype, lb: usize, ub: usize, dc: isize) bool {
    const c1: isize = @as(isize, @intCast(self.c1)) + dc;
    const c2: isize = @as(isize, @intCast(self.c2)) + dc;
    if (c1 >= lb and c2 <= ub) {
        self.c1 = @intCast(c1);
        self.c2 = @intCast(c2);
        return true;
    }
    return false;
}

pub fn startTextEdit(self: anytype) !void {
    std.debug.assert(self.state == .idle);
    std.debug.assert(self.imtui.focused(self.control()));
    try self.text_orig.replaceRange(self.imtui.allocator, 0, self.text_orig.items.len, self.text.items);
    self.state = .text_edit;
}
