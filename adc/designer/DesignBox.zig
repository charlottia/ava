const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");

const DesignBox = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    root: *DesignRoot.Impl,
    id: usize,
    dialog: *DesignDialog.Impl,

    // visible state
    r1: usize,
    c1: usize,
    r2: usize,
    c2: usize,
    text: std.ArrayListUnmanaged(u8),

    // internal state
    text_orig: std.ArrayListUnmanaged(u8) = .{},

    state: union(enum) {
        idle,
        move: struct {
            origin_row: usize,
            origin_col: usize,
            edit_eligible: bool,
        },
        resize: struct { cix: usize },
        text_edit,
    } = .idle,

    text_start: usize = undefined,

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

    pub fn describe(self: *Impl, _: *DesignRoot.Impl, _: *DesignDialog.Impl, _: usize, _: usize, _: usize, _: usize, _: usize, _: []const u8) void {
        const r1 = self.dialog.r1 + self.r1;
        const c1 = self.dialog.c1 + self.c1;
        const r2 = self.dialog.r1 + self.r2;
        const c2 = self.dialog.c1 + self.c2;

        self.imtui.text_mode.box(r1, c1, r2, c2, 0x70);

        if (self.text.items.len > 0) {
            self.text_start = c1 + (c2 - c1 -| self.text.items.len) / 2;
            self.imtui.text_mode.paint(r1, self.text_start - 1, r1 + 1, self.text_start + self.text.items.len + 1, 0x70, 0);
            self.imtui.text_mode.write(r1, self.text_start, self.text.items);
        } else self.text_start = c1 + (c2 - c1) / 2;

        self.imtui.text_mode.cursor_inhibit = true;

        if (!self.imtui.focused(self.control())) {
            if (self.imtui.focus_stack.items.len > 1 and !self.root.focus_idle)
                return;

            if (isMouseOver(self) and !(self.root.focus_idle and self.imtui.focus_stack.getLast().isMouseOver()))
                self.imtui.text_mode.paintColour(r1 - 1, c1 - 1, r2 + 1, c2 + 1, 0x20, .outline);
        } else switch (self.state) {
            .idle => {
                for (self.corners()) |corner|
                    if (self.imtui.text_mode.mouse_row == corner.r and self.imtui.text_mode.mouse_col == corner.c) {
                        self.imtui.text_mode.paintColour(corner.r - 1, corner.c - 1, corner.r + 2, corner.c + 2, 0xd0, .outline);
                        return;
                    };

                if (self.imtui.text_mode.mouse_row == r1 and
                    self.imtui.text_mode.mouse_col >= self.text_start - 1 and
                    self.imtui.text_mode.mouse_col < self.text_start + self.text.items.len + 1)
                {
                    self.imtui.text_mode.paintColour(r1, self.text_start - 1, r1 + 1, self.text_start + self.text.items.len + 1, 0xd0, .fill);
                    return;
                }

                const border_colour: u8 = if (isMouseOver(self)) 0xd0 else 0x50;
                self.imtui.text_mode.paintColour(r1 - 1, c1 - 1, r2 + 1, c2 + 1, border_colour, .outline);
            },
            .move, .resize => {},
            .text_edit => {
                self.imtui.text_mode.cursor_row = r1;
                self.imtui.text_mode.cursor_col = self.text_start + self.text.items.len;
                self.imtui.text_mode.cursor_inhibit = false;
            },
        }
    }

    fn parent(ptr: *const anyopaque) ?Imtui.Control {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.root.control();
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.text.deinit(self.imtui.allocator);
        self.text_orig.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn informRoot(self: *Impl) void {
        self.root.focus_idle = self.state == .idle;
        self.root.editing_text = self.state == .text_edit;
    }

    fn corners(self: *const Impl) [4]struct { r: usize, c: usize } {
        return .{
            .{ .r = self.dialog.r1 + self.r1, .c = self.dialog.c1 + self.c1 },
            .{ .r = self.dialog.r1 + self.r1, .c = self.dialog.c1 + self.c2 - 1 },
            .{ .r = self.dialog.r1 + self.r2 - 1, .c = self.dialog.c1 + self.c1 },
            .{ .r = self.dialog.r1 + self.r2 - 1, .c = self.dialog.c1 + self.c2 - 1 },
        };
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));

        switch (self.state) {
            .idle => switch (keycode) {
                .up => {
                    if (modifiers.get(.left_shift) or modifiers.get(.right_shift))
                        self.r2 -|= 1
                    else
                        _ = self.adjustRow(-1);
                },
                .down => {
                    if (modifiers.get(.left_shift) or modifiers.get(.right_shift))
                        self.r2 += 1
                    else
                        _ = self.adjustRow(1);
                },
                .left => {
                    if (modifiers.get(.left_shift) or modifiers.get(.right_shift))
                        self.c2 -|= 1
                    else
                        _ = self.adjustCol(-1);
                },
                .right => {
                    if (modifiers.get(.left_shift) or modifiers.get(.right_shift))
                        self.c2 += 1
                    else
                        _ = self.adjustCol(1);
                },
                else => return self.imtui.fallbackKeyPress(keycode, modifiers),
            },
            .move, .resize => {},
            .text_edit => switch (keycode) {
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
            },
        }
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.state == .text_edit or
            (self.imtui.mouse_row >= self.dialog.r1 + self.r1 and
            self.imtui.mouse_row < self.dialog.r1 + self.r2 and
            self.imtui.mouse_col >= self.dialog.c1 + self.c1 and
            self.imtui.mouse_col < self.dialog.c1 + self.c2 and
            (self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 or
            self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r2 - 1 or
            self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c1 or
            self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c2 - 1));
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
                .edit_eligible = false,
            } };
            try self.imtui.focus(self.control());
            return self.control();
        } else switch (self.state) {
            .idle => {
                for (self.corners(), 0..) |corner, cix|
                    if (self.imtui.text_mode.mouse_row == corner.r and self.imtui.text_mode.mouse_col == corner.c) {
                        self.state = .{ .resize = .{ .cix = cix } };
                        return self.control();
                    };

                const edit_eligible = self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and
                    self.imtui.text_mode.mouse_col >= self.text_start - 1 and
                    self.imtui.text_mode.mouse_col < self.text_start + self.text.items.len + 1;

                self.state = .{ .move = .{
                    .origin_row = self.imtui.text_mode.mouse_row,
                    .origin_col = self.imtui.text_mode.mouse_col,
                    .edit_eligible = edit_eligible,
                } };
                return self.control();
            },
            .text_edit => {
                if (!(self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and
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

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
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
                    0, 1 => self.r1 = self.imtui.text_mode.mouse_row,
                    2, 3 => self.r2 = self.imtui.text_mode.mouse_row + 1,
                    else => unreachable,
                }
                switch (d.cix) {
                    0, 2 => self.c1 = self.imtui.text_mode.mouse_col,
                    1, 3 => self.c2 = self.imtui.text_mode.mouse_col + 1,
                    else => unreachable,
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
            .move => |d| {
                self.state = .idle;
                if (d.edit_eligible)
                    try self.startTextEdit();
            },
            .resize => self.state = .idle,
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
        if (c1 > 0 and c2 < self.dialog.c2 - self.dialog.c1) {
            self.c1 = @intCast(c1);
            self.c2 = @intCast(c2);
            return true;
        }
        return false;
    }

    pub fn startTextEdit(self: *Impl) !void {
        std.debug.assert(self.state == .idle);
        std.debug.assert(self.imtui.focused(self.control()));
        try self.text_orig.replaceRange(self.imtui.allocator, 0, self.text_orig.items.len, self.text.items);
        self.state = .text_edit;
    }

    pub fn populateHelpLine(self: *Impl, offset: *usize) !void {
        var edit_button = try self.imtui.button(24, offset.*, 0x30, "<Enter=Edit Text>");
        if (edit_button.chosen())
            try self.startTextEdit();
        offset.* += "<Enter=Edit Text> ".len;
    }

    pub fn createMenu(self: *Impl, menubar: Imtui.Controls.Menubar) !void {
        var menu = try menubar.menu("&Box", 0);

        var edit_text = (try menu.item("&Edit Text...")).shortcut(.@"return", null).help("Edits the box's text");
        if (edit_text.chosen())
            try self.startTextEdit();

        try menu.end();
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: *DesignRoot.Impl, _: *DesignDialog.Impl, id: usize, _: usize, _: usize, _: usize, _: usize, _: []const u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}", .{ "designer.DesignBox", id });
}

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, id: usize, r1: usize, c1: usize, r2: usize, c2: usize, text: []const u8) !DesignBox {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .root = root,
        .dialog = dialog,
        .id = id,
        .r1 = r1,
        .c1 = c1,
        .r2 = r2,
        .c2 = c2,
        .text = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, text)),
    };
    d.describe(root, dialog, id, r1, c1, r2, c2, text);
    return .{ .impl = d };
}

pub const Schema = struct {
    id: usize,
    r1: usize,
    c1: usize,
    r2: usize,
    c2: usize,
    text: []const u8,

    pub fn deinit(self: Schema, allocator: Allocator) void {
        allocator.free(self.text);
    }

    pub fn bufPrintFocusLabel(self: *const Schema, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "[Box] {s}", .{self.text});
    }
};

pub fn sync(self: DesignBox, allocator: Allocator, schema: *Schema) !void {
    schema.id = self.impl.id;
    schema.r1 = self.impl.r1;
    schema.c1 = self.impl.c1;
    schema.r2 = self.impl.r2;
    schema.c2 = self.impl.c2;
    if (!std.mem.eql(u8, schema.text, self.impl.text.items)) {
        allocator.free(schema.text);
        schema.text = try allocator.dupe(u8, self.impl.text.items);
    }
}
