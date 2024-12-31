const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");

const DesignButton = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    root: *DesignRoot.Impl,
    id: usize,
    dialog: *DesignDialog.Impl,

    // visible state
    r1: usize,
    c1: usize,
    label: std.ArrayListUnmanaged(u8),
    primary: bool,
    cancel: bool,

    // internal state
    r2: usize = undefined,
    c2: usize = undefined,
    label_orig: std.ArrayListUnmanaged(u8) = .{},

    state: union(enum) {
        idle,
        move: struct {
            origin_row: usize,
            origin_col: usize,
            edit_eligible: bool,
        },
        label_edit,
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

    pub fn describe(self: *Impl, _: *DesignRoot.Impl, _: *DesignDialog.Impl, _: usize, _: usize, _: usize, _: []const u8, _: bool, _: bool) void {
        self.r2 = self.r1 + 1;
        self.c2 = self.c1 + 4 + self.label.items.len;

        const r1 = self.dialog.r1 + self.r1;
        const c1 = self.dialog.c1 + self.c1;
        const r2 = self.dialog.r1 + self.r2;
        const c2 = self.dialog.c1 + self.c2;

        if (self.primary) {
            self.imtui.text_mode.paintColour(r1, c1, r2, c1 + 1, 0x7f, .fill);
            self.imtui.text_mode.paintColour(r1, c2 - 1, r2, c2, 0x7f, .fill);
        }

        self.imtui.text_mode.write(r1, c1, "<");
        self.imtui.text_mode.writeAccelerated(r1, c1 + 2, self.label.items, true);
        self.imtui.text_mode.write(r1, c2 - 1, ">");

        if (!self.imtui.focused(self.control())) {
            if (self.imtui.focus_stack.items.len > 1 and !self.root.focus_idle)
                return;

            if (isMouseOver(self) and !(self.root.focus_idle and self.imtui.focus_stack.getLast().isMouseOver()))
                self.imtui.text_mode.paintColour(r1, c1, r2, c2, 0x20, .fill);
        } else switch (self.state) {
            .idle => {
                self.imtui.text_mode.paintColour(r1, c1, r2, c2, 0x50, .fill);
            },
            .move => |_| {},
            .label_edit => {
                self.imtui.text_mode.cursor_row = r1;
                self.imtui.text_mode.cursor_col = c1 + 2 + self.label.items.len;
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
        self.label.deinit(self.imtui.allocator);
        self.label_orig.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn informRoot(self: *Impl) void {
        self.root.focus_idle = self.state == .idle;
        self.root.editing_text = self.state == .label_edit;
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        switch (self.state) {
            .idle => switch (keycode) {
                .up => _ = self.adjustRow(-1),
                .down => _ = self.adjustRow(1),
                .left => _ = self.adjustCol(-1),
                .right => _ = self.adjustCol(1),
                else => return self.imtui.fallbackKeyPress(keycode, modifiers),
            },
            .move => {},
            .label_edit => switch (keycode) {
                .backspace => if (self.label.items.len > 0) {
                    if (modifiers.get(.left_control) or modifiers.get(.right_control))
                        self.label.items.len = 0
                    else
                        self.label.items.len -= 1;
                },
                .@"return" => self.state = .idle,
                .escape => {
                    self.state = .idle;
                    try self.label.replaceRange(self.imtui.allocator, 0, self.label.items.len, self.label_orig.items);
                },
                else => if (Imtui.Controls.isPrintableKey(keycode)) {
                    try self.label.append(self.imtui.allocator, Imtui.Controls.getCharacter(keycode, modifiers));
                },
            },
        }
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.state == .label_edit or
            (self.imtui.mouse_row >= self.dialog.r1 + self.r1 and
            self.imtui.mouse_row < self.dialog.r1 + self.r2 and
            self.imtui.mouse_col >= self.dialog.c1 + self.c1 and
            self.imtui.mouse_col < self.dialog.c1 + self.c2);
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
                self.state = .{ .move = .{
                    .origin_row = self.imtui.text_mode.mouse_row,
                    .origin_col = self.imtui.text_mode.mouse_col,
                    .edit_eligible = true,
                } };
                return self.control();
            },
            .label_edit => {
                if (!(self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and
                    self.imtui.text_mode.mouse_col >= self.dialog.c1 + self.c1 + 1 and
                    self.imtui.text_mode.mouse_col < self.dialog.c1 + self.c2 - 1))
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
                    try self.startLabelEdit();
            },
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

    pub fn startLabelEdit(self: *Impl) !void {
        std.debug.assert(self.state == .idle);
        std.debug.assert(self.imtui.focused(self.control()));
        try self.label_orig.replaceRange(self.imtui.allocator, 0, self.label_orig.items.len, self.label.items);
        self.state = .label_edit;
    }

    pub fn populateHelpLine(self: *Impl, offset: *usize) !void {
        var edit_button = try self.imtui.button(24, offset.*, 0x30, "<Enter=Edit Label>");
        if (edit_button.chosen())
            try self.startLabelEdit();
        offset.* += "<Enter=Edit Label> ".len;

        var delete_button = try self.imtui.button(24, offset.*, 0x30, "<Del=Delete>");
        if (delete_button.chosen())
            self.root.designer.removeDesignControlById(self.id);
        offset.* += "<Del=Delete> ".len;
    }

    pub fn bufPrintFocusLabel(self: *const Impl, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "[Button] {s}", .{self.label.items});
    }

    pub fn createMenu(self: *Impl, menubar: Imtui.Controls.Menubar) !void {
        var menu = try menubar.menu("&Button", 0);

        var edit_label = (try menu.item("&Edit Label...")).shortcut(.@"return", null).help("Edits the button's label");
        if (edit_label.chosen())
            try self.startLabelEdit();

        var primary = (try menu.item("&Primary")).help("Toggles the button's primary status");
        if (self.primary)
            primary.bullet();
        if (primary.chosen())
            self.primary = !self.primary;

        var cancel = (try menu.item("&Cancel")).help("Toggles the button's cancel status");
        if (self.cancel)
            cancel.bullet();
        if (cancel.chosen())
            self.cancel = !self.cancel;

        try menu.separator();

        var delete = (try menu.item("Delete")).shortcut(.delete, null).help("Deletes the button");
        if (delete.chosen())
            self.root.designer.removeDesignControlById(self.id);

        try menu.end();
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: *DesignRoot.Impl, _: *DesignDialog.Impl, id: usize, _: usize, _: usize, _: []const u8, _: bool, _: bool) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}", .{ "designer.DesignButton", id });
}

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, id: usize, r1: usize, c1: usize, label: []const u8, primary: bool, cancel: bool) !DesignButton {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .root = root,
        .dialog = dialog,
        .id = id,
        .r1 = r1,
        .c1 = c1,
        .label = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, label)),
        .primary = primary,
        .cancel = cancel,
    };
    d.describe(root, dialog, id, r1, c1, label, primary, cancel);
    return .{ .impl = d };
}

pub const Schema = struct {
    id: usize,
    r1: usize,
    c1: usize,
    label: []const u8,
    primary: bool,
    cancel: bool,

    pub fn deinit(self: Schema, allocator: Allocator) void {
        allocator.free(self.label);
    }
};

pub fn sync(self: DesignButton, allocator: Allocator, schema: *Schema) !void {
    schema.id = self.impl.id;
    schema.r1 = self.impl.r1;
    schema.c1 = self.impl.c1;
    if (!std.mem.eql(u8, schema.label, self.impl.label.items)) {
        allocator.free(schema.label);
        schema.label = try allocator.dupe(u8, self.impl.label.items);
    }
    schema.primary = self.impl.primary;
    schema.cancel = self.impl.cancel;
}
