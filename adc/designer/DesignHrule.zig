const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const ini = @import("ini");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");

const DesignHrule = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    root: *DesignRoot.Impl,
    id: usize,
    dialog: *DesignDialog.Impl,

    // visible state
    r1: usize,
    c1: usize,
    c2: usize,

    // internal state
    r2: usize = undefined,

    state: union(enum) {
        idle,
        move: struct {
            origin_row: usize,
            origin_col: usize,
        },
        resize: struct { end: u1 },
    } = .idle,

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .parent = parent,
                .deinit = deinit,
                .handleKeyPress = handleKeyPress,
                .handleKeyUp = handleKeyUp,
                .isMouseOver = isMouseOver,
                .handleMouseDown = handleMouseDown,
                .handleMouseDrag = handleMouseDrag,
                .handleMouseUp = handleMouseUp,
            },
        };
    }

    pub fn describe(self: *Impl, _: *DesignRoot.Impl, _: *DesignDialog.Impl, _: usize, _: usize, _: usize, _: usize) void {
        self.r2 = self.r1 + 1;

        const r1 = self.dialog.r1 + self.r1;
        const r2 = self.dialog.r1 + self.r2;
        const c1 = self.dialog.c1 + self.c1;
        const c2 = self.dialog.c1 + self.c2;

        self.imtui.text_mode.paint(r1, c1, r2, c2, 0x70, .Horizontal);
        if (self.c1 == 0)
            self.imtui.text_mode.draw(r1, c1, 0x70, .VerticalRight);
        if (self.c2 == self.dialog.c2 - self.dialog.c1)
            self.imtui.text_mode.draw(r1, c2 - 1, 0x70, .VerticalLeft);

        if (!self.imtui.focused(self.control())) {
            if (self.imtui.focus_stack.items.len > 1 and !self.root.focus_idle)
                return;

            if (isMouseOver(self))
                self.imtui.text_mode.paintColour(r1, c1, r2, c2, 0x20, .fill);
        } else switch (self.state) {
            .idle => {
                if (self.imtui.text_mode.mouse_row == r1 and self.imtui.text_mode.mouse_col == c1) {
                    self.imtui.text_mode.paintColour(r1 - 1, c1 - 1, r1 + 2, c1 + 2, 0xd0, .outline);
                    return;
                }

                if (self.imtui.text_mode.mouse_row == r1 and self.imtui.text_mode.mouse_col == c2 - 1) {
                    self.imtui.text_mode.paintColour(r1 - 1, c2 - 2, r1 + 2, c2 + 1, 0xd0, .outline);
                    return;
                }

                const border_colour: u8 = if (isMouseOver(self)) 0xd0 else 0x50;
                self.imtui.text_mode.paintColour(r1, c1, r2, c2, border_colour, .fill);
            },
            .move, .resize => {},
        }
    }

    fn parent(ptr: *const anyopaque) ?Imtui.Control {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.root.control();
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.imtui.allocator.destroy(self);
    }

    pub fn informRoot(self: *Impl) void {
        self.root.focus_idle = self.state == .idle;
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        switch (self.state) {
            .idle => switch (keycode) {
                .up => _ = self.adjustRow(-1),
                .down => _ = self.adjustRow(1),
                .left => {
                    if (modifiers.get(.left_shift) or modifiers.get(.right_shift))
                        self.c2 -|= 1
                    else
                        _ = self.adjustCol(-1);
                },
                .right => {
                    if (modifiers.get(.left_shift) or modifiers.get(.right_shift))
                        self.c2 = @min(self.c2 + 1, self.dialog.c2 - self.dialog.c1)
                    else
                        _ = self.adjustCol(1);
                },
                else => return self.imtui.fallbackKeyPress(keycode, modifiers),
            },
            .move, .resize => {},
        }
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.imtui.mouse_row >= self.dialog.r1 + self.r1 and
            self.imtui.mouse_row < self.dialog.r1 + self.r2 and
            self.imtui.mouse_col >= self.dialog.c1 + self.c1 and
            self.imtui.mouse_col < self.dialog.c1 + self.c2;
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));

        if (cm) return null;

        const focused = self.imtui.focused(self.control());
        if (!isMouseOver(ptr))
            if (try self.imtui.fallbackMouseDown(b, clicks, cm)) |r|
                return r.@"0"
            else {
                if (focused) self.imtui.unfocusAnywhere(self.control());
                return null;
            };

        if (b != .left) return null;

        if (!focused) {
            self.state = .{ .move = .{
                .origin_row = self.imtui.text_mode.mouse_row,
                .origin_col = self.imtui.text_mode.mouse_col,
            } };
            try self.imtui.focus(self.control());
            return self.control();
        } else switch (self.state) {
            .idle => {
                if (self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and
                    self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c1)
                {
                    self.state = .{ .resize = .{ .end = 0 } };
                    return self.control();
                }

                if (self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and
                    self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c2 - 1)
                {
                    self.state = .{ .resize = .{ .end = 1 } };
                    return self.control();
                }

                self.state = .{ .move = .{
                    .origin_row = self.imtui.text_mode.mouse_row,
                    .origin_col = self.imtui.text_mode.mouse_col,
                } };
                return self.control();
            },
            else => return null,
        }
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
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

    fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;
        _ = clicks;

        switch (self.state) {
            .move, .resize => self.state = .idle,
            else => unreachable,
        }
    }

    fn adjustRow(self: *Impl, dr: isize) bool {
        const r1: isize = @as(isize, @intCast(self.r1)) + dr;
        const r2: isize = @as(isize, @intCast(self.r2)) + dr;
        if (r1 > 0 and r2 < self.dialog.r2 - self.dialog.r1) {
            self.r1 = @intCast(r1);
            self.r2 = @intCast(r2);
            return true;
        }
        return false;
    }

    fn adjustCol(self: *Impl, dc: isize) bool {
        const c1: isize = @as(isize, @intCast(self.c1)) + dc;
        const c2: isize = @as(isize, @intCast(self.c2)) + dc;
        // NOTE: this differs from other controls in that it's allowed to
        // overlap the left and right borders.
        if (c1 >= 0 and c2 <= self.dialog.c2 - self.dialog.c1) {
            self.c1 = @intCast(c1);
            self.c2 = @intCast(c2);
            return true;
        }
        return false;
    }

    pub fn populateHelpLine(self: *Impl, offset: *usize) !void {
        var delete_button = try self.imtui.button(24, offset.*, 0x30, "<Del=Delete>");
        if (delete_button.chosen())
            self.root.designer.removeDesignControlById(self.id);
        offset.* += "<Del=Delete> ".len;
    }

    pub fn createMenu(self: *Impl, menubar: Imtui.Controls.Menubar) !void {
        var menu = try menubar.menu("&Hrule", 0);

        var delete = (try menu.item("Delete")).shortcut(.delete, null).help("Deletes the hrule");
        if (delete.chosen())
            self.root.designer.removeDesignControlById(self.id);

        try menu.end();
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: *DesignRoot.Impl, _: *DesignDialog.Impl, id: usize, _: usize, _: usize, _: usize) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}", .{ "designer.DesignHrule", id });
}

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, id: usize, r1: usize, c1: usize, c2: usize) !DesignHrule {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .root = root,
        .dialog = dialog,
        .id = id,
        .r1 = r1,
        .c1 = c1,
        .c2 = c2,
    };
    d.describe(root, dialog, id, r1, c1, c2);
    return .{ .impl = d };
}

pub const Schema = struct {
    id: usize,
    r1: usize,
    c1: usize,
    c2: usize,

    pub fn deinit(_: Schema, _: Allocator) void {}
};

pub fn sync(self: DesignHrule, _: Allocator, schema: *Schema) !void {
    schema.id = self.impl.id;
    schema.r1 = self.impl.r1;
    schema.c1 = self.impl.c1;
    schema.c2 = self.impl.c2;
}
