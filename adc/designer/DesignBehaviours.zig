const std = @import("std");
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;
const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");

const Self = @This();

fn corners(r1: usize, c1: usize, r2: usize, c2: usize) [4]struct { r: usize, c: usize } {
    return .{
        .{ .r = r1, .c = c1 },
        .{ .r = r1, .c = c2 - 1 },
        .{ .r = r2 - 1, .c = c1 },
        .{ .r = r2 - 1, .c = c2 - 1 },
    };
}

fn StateForBehaviours(comptime behaviours: anytype) type {
    const Move = struct { origin_row: usize, origin_col: usize };
    const MoveWithEdit = struct { origin_row: usize, origin_col: usize, edit_eligible: bool };
    comptime var MoveKind: type = Move;

    comptime var StateEnumFields: []const std.builtin.Type.EnumField = &.{
        .{ .name = "idle", .value = 0 },
    };
    comptime var StateUnionFields: []const std.builtin.Type.UnionField = &.{
        .{ .name = "idle", .type = void, .alignment = 0 },
    };
    for (behaviours) |b| {
        if (b == .wh_resizable) {
            StateEnumFields = StateEnumFields ++ [_]std.builtin.Type.EnumField{
                .{ .name = "resize", .value = StateEnumFields.len },
            };
            StateUnionFields = StateUnionFields ++ [_]std.builtin.Type.UnionField{
                .{ .name = "resize", .type = struct { cix: u2 }, .alignment = @alignOf(struct { cix: u2 }) },
            };
        } else if (b == .width_resizable) {
            StateEnumFields = StateEnumFields ++ [_]std.builtin.Type.EnumField{
                .{ .name = "resize", .value = StateEnumFields.len },
            };
            StateUnionFields = StateUnionFields ++ [_]std.builtin.Type.UnionField{
                .{ .name = "resize", .type = struct { end: u1 }, .alignment = @alignOf(struct { end: u1 }) },
            };
        } else if (b == .text_editable) {
            MoveKind = MoveWithEdit;
            StateEnumFields = StateEnumFields ++ [_]std.builtin.Type.EnumField{
                .{ .name = "text_edit", .value = StateEnumFields.len },
            };
            StateUnionFields = StateUnionFields ++ [_]std.builtin.Type.UnionField{
                .{ .name = "text_edit", .type = std.ArrayListUnmanaged(u8), .alignment = @alignOf(std.ArrayListUnmanaged(u8)) },
            };
        } else if (b == .dialog) {
            // nop
        } else unreachable;
    }

    StateEnumFields = StateEnumFields ++ [_]std.builtin.Type.EnumField{
        .{ .name = "move", .value = StateEnumFields.len },
    };
    StateUnionFields = StateUnionFields ++ [_]std.builtin.Type.UnionField{
        .{ .name = "move", .type = MoveKind, .alignment = @alignOf(MoveKind) },
    };

    return @Type(.{ .Union = .{
        .layout = .auto,
        .tag_type = @Type(.{ .Enum = .{
            .tag_type = u8,
            .fields = StateEnumFields,
            .decls = &.{},
            .is_exhaustive = true,
        } }),
        .fields = StateUnionFields,
        .decls = &.{},
    } });
}

const Sizing = enum { autosized, width_resizable, wh_resizable };

fn archetypesForBehaviours(comptime behaviours: anytype) struct {
    sizing: Sizing,
    text_editable: bool,
    dialog: bool,
} {
    var sizing: Sizing = .autosized;
    var text_editable = false;
    var dialog = false;

    inline for (behaviours) |b|
        if (b == .wh_resizable) {
            sizing = .wh_resizable;
        } else if (b == .width_resizable) {
            sizing = .width_resizable;
        } else if (b == .text_editable) {
            text_editable = true;
        } else if (b == .dialog) {
            dialog = true;
        } else {
            @compileError("unknown behaviour: " ++ @tagName(b));
        };

    return .{ .sizing = sizing, .text_editable = text_editable, .dialog = dialog };
}

pub fn DesCon(comptime Config: type) type {
    // TODO: would be nice to automatically set r2/c2 undefined defaults where
    // applicable (autosized/width_resizable).
    //
    // XXX: inability to reify structs with decls makes things a bit more
    // awkward (and is unlikely to ever change); see
    // https://github.com/ziglang/zig/issues/6709.

    const Fields = if (@hasDecl(Config, "Fields")) Config.Fields else void;

    return struct {
        const Impl = @This();

        pub const Archetypes = archetypesForBehaviours(Config.behaviours);
        pub const State = StateForBehaviours(Config.behaviours);

        imtui: *Imtui,
        generation: usize,

        root: *DesignRoot.Impl,
        id: usize,
        // TODO: insert this and `text` dynamically to avoid unwanted defaults
        dialog: if (Archetypes.dialog) void else *DesignDialog.Impl = if (Archetypes.dialog) {} else undefined,

        // visible state
        r1: usize,
        c1: usize,
        r2: usize,
        c2: usize,
        // TODO: as above
        text: if (Archetypes.text_editable) std.ArrayListUnmanaged(u8) else void = if (Archetypes.text_editable) undefined else {},

        // TODO: as above
        fields: Fields = if (@hasDecl(Config, "Fields")) undefined else {},

        // internal state
        text_start: if (Archetypes.text_editable) usize else void = undefined,
        state: State = .idle,

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

        pub fn describe(self: *Impl) void {
            Config.describe(self);

            const r1 = (if (!Archetypes.dialog) self.dialog.r1 else 0) + self.r1;
            const c1 = (if (!Archetypes.dialog) self.dialog.c1 else 0) + self.c1;
            const r2 = (if (!Archetypes.dialog) self.dialog.r1 else 0) + self.r2;
            const c2 = (if (!Archetypes.dialog) self.dialog.c1 else 0) + self.c2;

            const c = self.control();

            if (!self.imtui.focused(self.control())) {
                if (self.imtui.focus_stack.items.len > 1 and !self.root.focus_idle)
                    return;

                if (c.isMouseOver() and !(self.root.focus_idle and self.imtui.focus_stack.getLast().isMouseOver()))
                    self.border(0x20);
                return;
            } else switch (self.state) {
                .idle => {
                    if (Archetypes.sizing == .autosized) {
                        // nop
                    } else if (Archetypes.sizing == .width_resizable) {
                        if (self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c1) {
                            self.imtui.text_mode.paintColour(self.dialog.r1 + self.r1 - 1, self.dialog.c1 + self.c1 - 1, self.dialog.r1 + self.r1 + 2, self.dialog.c1 + self.c1 + 2, 0xd0, .outline);
                            return;
                        }

                        if (self.imtui.text_mode.mouse_row == self.dialog.r1 + self.r1 and self.imtui.text_mode.mouse_col == self.dialog.c1 + self.c2 - 1) {
                            self.imtui.text_mode.paintColour(self.dialog.r1 + self.r1 - 1, self.dialog.c1 + self.c2 - 2, self.dialog.r1 + self.r1 + 2, self.dialog.c1 + self.c2 + 1, 0xd0, .outline);
                            return;
                        }
                    } else if (Archetypes.sizing == .wh_resizable) {
                        for (corners(r1, c1, r2, c2)) |corner|
                            if (self.imtui.text_mode.mouse_row == corner.r and self.imtui.text_mode.mouse_col == corner.c) {
                                self.imtui.text_mode.paintColour(corner.r - 1, corner.c - 1, corner.r + 2, corner.c + 2, 0xd0, .outline);
                                return;
                            };

                        if (Archetypes.text_editable) {
                            if (self.imtui.text_mode.mouse_row == r1 and
                                self.imtui.text_mode.mouse_col >= self.text_start - 1 and
                                self.imtui.text_mode.mouse_col < self.text_start + self.text.items.len + 1)
                            {
                                self.imtui.text_mode.paintColour(r1, self.text_start - 1, r1 + 1, self.text_start + self.text.items.len + 1, 0xd0, .fill);
                                return;
                            }
                        }
                    } else {
                        unreachable;
                    }

                    const border_colour: u8 = if (c.isMouseOver()) 0xd0 else 0x50;
                    self.border(border_colour);
                },
                .move => {},
                inline else => |_, tag| {
                    if (Archetypes.sizing != .autosized and tag == .resize)
                        return
                    else if (tag == .text_edit) {
                        self.imtui.text_mode.cursor_row = r1;
                        self.imtui.text_mode.cursor_col = self.text_start + Imtui.Controls.lenWithoutAccelerators(self.text.items);
                        self.imtui.text_mode.cursor_inhibit = false;
                    } else {
                        unreachable;
                    }
                },
            }
        }

        fn parent(ptr: *const anyopaque) ?Imtui.Control {
            const self: *const Impl = @ptrCast(@alignCast(ptr));
            return self.root.control();
        }

        pub fn deinit(ptr: *anyopaque) void {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            if (@TypeOf(self.text) != void)
                self.text.deinit(self.imtui.allocator);
            if (Archetypes.text_editable)
                if (self.state == .text_edit)
                    self.state.text_edit.deinit(self.imtui.allocator);
            self.imtui.allocator.destroy(self);
        }

        pub fn informRoot(self: *Impl) void {
            self.root.focus_idle = self.state == .idle;

            if (Archetypes.text_editable)
                self.root.editing_text = self.state == .text_edit;
        }

        fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
            const self: *Impl = @ptrCast(@alignCast(ptr));

            switch (self.state) {
                .idle => switch (keycode) {
                    .up => if ((Archetypes.sizing == .wh_resizable) and (modifiers.get(.left_shift) or modifiers.get(.right_shift))) {
                        self.r2 -|= 1;
                    } else {
                        _ = self.adjustRow(-1);
                    },
                    .down => if ((Archetypes.sizing == .wh_resizable) and (modifiers.get(.left_shift) or modifiers.get(.right_shift))) {
                        self.r2 += 1;
                    } else {
                        _ = self.adjustRow(1);
                    },
                    .left => if ((Archetypes.sizing != .autosized) and (modifiers.get(.left_shift) or modifiers.get(.right_shift))) {
                        self.c2 -|= 1;
                    } else {
                        _ = self.adjustCol(-1);
                    },
                    .right => if ((Archetypes.sizing != .autosized) and (modifiers.get(.left_shift) or modifiers.get(.right_shift))) {
                        self.c2 += 1;
                    } else {
                        _ = self.adjustCol(1);
                    },
                    else => try self.imtui.fallbackKeyPress(keycode, modifiers),
                },
                .move => {},
                inline else => |_, tag| {
                    if (Archetypes.sizing != .autosized and tag == .resize)
                        return
                    else if (tag == .text_edit) switch (keycode) {
                        .backspace => if (self.text.items.len > 0) {
                            if (modifiers.get(.left_control) or modifiers.get(.right_control))
                                self.text.items.len = 0
                            else
                                self.text.items.len -= 1;
                        },
                        .@"return" => {
                            self.state.text_edit.deinit(self.imtui.allocator);
                            self.state = .idle;
                        },
                        .escape => {
                            try self.text.replaceRange(self.imtui.allocator, 0, self.text.items.len, self.state.text_edit.items);
                            self.state.text_edit.deinit(self.imtui.allocator);
                            self.state = .idle;
                        },
                        else => if (Imtui.Controls.isPrintableKey(keycode)) {
                            try self.text.append(self.imtui.allocator, Imtui.Controls.getCharacter(keycode, modifiers));
                        },
                    } else {
                        unreachable;
                    }
                },
            }
        }

        fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

        fn isMouseOver(ptr: *const anyopaque) bool {
            const self: *const Impl = @ptrCast(@alignCast(ptr));
            if (Archetypes.text_editable)
                if (self.state == .text_edit)
                    return true;

            const r1 = (if (!Archetypes.dialog) self.dialog.r1 else 0) + self.r1;
            const c1 = (if (!Archetypes.dialog) self.dialog.c1 else 0) + self.c1;
            const r2 = (if (!Archetypes.dialog) self.dialog.r1 else 0) + self.r2;
            const c2 = (if (!Archetypes.dialog) self.dialog.c1 else 0) + self.c2;

            return switch (Archetypes.sizing) {
                .autosized, .width_resizable => self.imtui.mouse_row >= r1 and self.imtui.mouse_row < r2 and
                    self.imtui.mouse_col >= c1 and self.imtui.mouse_col < c2,
                .wh_resizable => self.imtui.mouse_row >= r1 and self.imtui.mouse_row < r2 and
                    self.imtui.mouse_col >= c1 and self.imtui.mouse_col < c2 and
                    (self.imtui.text_mode.mouse_row == r1 or self.imtui.text_mode.mouse_row == r2 - 1 or
                    self.imtui.text_mode.mouse_col == c1 or self.imtui.text_mode.mouse_col == c2 - 1),
            };
        }

        fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
            const self: *Impl = @ptrCast(@alignCast(ptr));

            const c = self.control();

            const r1 = (if (!Archetypes.dialog) self.dialog.r1 else 0) + self.r1;
            const c1 = (if (!Archetypes.dialog) self.dialog.c1 else 0) + self.c1;
            const r2 = (if (!Archetypes.dialog) self.dialog.r1 else 0) + self.r2;
            const c2 = (if (!Archetypes.dialog) self.dialog.c1 else 0) + self.c2;

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
                if (Archetypes.text_editable)
                    self.state = .{ .move = .{
                        .origin_row = self.imtui.text_mode.mouse_row,
                        .origin_col = self.imtui.text_mode.mouse_col,
                        .edit_eligible = false,
                    } }
                else
                    self.state = .{ .move = .{
                        .origin_row = self.imtui.text_mode.mouse_row,
                        .origin_col = self.imtui.text_mode.mouse_col,
                    } };
                try self.imtui.focus(c);
                return c;
            } else switch (self.state) {
                .idle => {
                    if (Archetypes.sizing == .autosized) {
                        // nop
                    } else if (Archetypes.sizing == .width_resizable) {
                        if (self.imtui.text_mode.mouse_row == r1 and self.imtui.text_mode.mouse_col == c1) {
                            self.state = .{ .resize = .{ .end = 0 } };
                            return c;
                        }

                        if (self.imtui.text_mode.mouse_row == r1 and self.imtui.text_mode.mouse_col == c2 - 1) {
                            self.state = .{ .resize = .{ .end = 1 } };
                            return c;
                        }
                    } else if (Archetypes.sizing == .wh_resizable) {
                        for (corners(r1, c1, r2, c2), 0..) |corner, cix|
                            if (self.imtui.text_mode.mouse_row == corner.r and
                                self.imtui.text_mode.mouse_col == corner.c)
                            {
                                self.state = .{ .resize = .{ .cix = @intCast(cix) } };
                                return c;
                            };
                    } else {
                        unreachable;
                    }

                    if (Archetypes.text_editable) {
                        const edit_eligible = Archetypes.sizing == .autosized or (self.imtui.text_mode.mouse_row == r1 and
                            self.imtui.text_mode.mouse_col >= self.text_start - 1 and
                            self.imtui.text_mode.mouse_col < self.text_start + self.text.items.len + 1);

                        self.state = .{ .move = .{
                            .origin_row = self.imtui.text_mode.mouse_row,
                            .origin_col = self.imtui.text_mode.mouse_col,
                            .edit_eligible = edit_eligible,
                        } };
                        return c;
                    } else {
                        self.state = .{ .move = .{
                            .origin_row = self.imtui.text_mode.mouse_row,
                            .origin_col = self.imtui.text_mode.mouse_col,
                        } };
                        return c;
                    }
                },
                .move => return null,
                inline else => |_, tag| {
                    if (Archetypes.sizing != .autosized and tag == .resize)
                        return null
                    else if (tag == .text_edit) {
                        if (!(self.imtui.text_mode.mouse_row == r1 and
                            self.imtui.text_mode.mouse_col >= self.text_start - 1 and
                            self.imtui.text_mode.mouse_col < self.text_start + Imtui.Controls.lenWithoutAccelerators(self.text.items) + 1))
                        {
                            self.state.text_edit.deinit(self.imtui.allocator);
                            self.state = .idle;
                        }

                        return null;
                    } else {
                        unreachable;
                    }
                },
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
                        if (Archetypes.text_editable)
                            d.edit_eligible = false;
                    }
                    if (self.adjustCol(dc)) {
                        d.origin_col = @intCast(@as(isize, @intCast(d.origin_col)) + dc);
                        if (Archetypes.text_editable)
                            d.edit_eligible = false;
                    }
                },
                inline else => |d, tag| {
                    if (Archetypes.sizing != .autosized and tag == .resize) {
                        if (Archetypes.sizing == .width_resizable)
                            switch (d.end) {
                                0 => self.c1 = self.imtui.text_mode.mouse_col -| self.dialog.c1,
                                1 => self.c2 = @min(self.imtui.text_mode.mouse_col -| self.dialog.c1 + 1, self.dialog.c2 - self.dialog.c1),
                            }
                        else if (Archetypes.sizing == .wh_resizable) {
                            switch (d.cix) {
                                0, 1 => self.r1 = self.imtui.text_mode.mouse_row - (if (!Archetypes.dialog) self.dialog.r1 else 0),
                                2, 3 => self.r2 = self.imtui.text_mode.mouse_row + 1 - (if (!Archetypes.dialog) self.dialog.r1 else 0),
                            }
                            switch (d.cix) {
                                0, 2 => self.c1 = self.imtui.text_mode.mouse_col - (if (!Archetypes.dialog) self.dialog.c1 else 0),
                                1, 3 => self.c2 = self.imtui.text_mode.mouse_col + 1 - (if (!Archetypes.dialog) self.dialog.c1 else 0),
                            }
                        } else unreachable;
                    } else {
                        unreachable;
                    }
                },
            }
        }

        fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
            const self: *Impl = @ptrCast(@alignCast(ptr));
            _ = b;
            _ = clicks;

            switch (self.state) {
                .move => |d| {
                    self.state = .idle;
                    if (comptime Archetypes.text_editable)
                        if (d.edit_eligible)
                            try self.startTextEdit();
                },
                inline else => |_, tag| {
                    if (Archetypes.sizing != .autosized and tag == .resize) {
                        self.state = .idle;
                    } else {
                        unreachable;
                    }
                },
            }
        }

        pub fn adjustRow(self: *Impl, dr: isize) bool {
            const lb = 1; // XXX
            const ub = if (Archetypes.dialog) (self.imtui.text_mode.H - 1) else (self.dialog.r2 - self.dialog.r1 - 1);

            const r1: isize = @as(isize, @intCast(self.r1)) + dr;
            const r2: isize = @as(isize, @intCast(self.r2)) + dr;
            if (r1 >= lb and r2 <= ub) {
                self.r1 = @intCast(r1);
                self.r2 = @intCast(r2);
                return true;
            }
            return false;
        }

        pub fn adjustCol(self: *Impl, dc: isize) bool {
            const lb = if (Archetypes.sizing == .width_resizable)
                0 // XXX: hack for Hrule. It needs to override this itself.
            else
                1;
            const ub = if (Archetypes.dialog)
                self.imtui.text_mode.W - 1
            else if (Archetypes.sizing == .width_resizable)
                self.dialog.c2 - self.dialog.c1 // XXX: hack for Hrule. It needs to override this itself.
            else
                self.dialog.c2 - self.dialog.c1 - 1;

            const c1: isize = @as(isize, @intCast(self.c1)) + dc;
            const c2: isize = @as(isize, @intCast(self.c2)) + dc;
            if (c1 >= lb and c2 <= ub) {
                self.c1 = @intCast(c1);
                self.c2 = @intCast(c2);
                return true;
            }
            return false;
        }

        pub fn populateHelpLine(self: *Impl, offset: *usize) !void {
            if (Archetypes.text_editable) {
                var edit_button = try self.imtui.button(24, offset.*, 0x30, "<Enter=Edit Text>");
                if (edit_button.chosen())
                    try self.startTextEdit();
                offset.* += "<Enter=Edit Text> ".len;
            }

            if (!Archetypes.dialog) {
                var delete_button = try self.imtui.button(24, offset.*, 0x30, "<Del=Delete>");
                if (delete_button.chosen())
                    self.root.designer.removeDesignControlById(self.id);
                offset.* += "<Del=Delete> ".len;
            }
        }

        pub fn createMenu(self: *Impl, menubar: Imtui.Controls.Menubar) !void {
            var menu = try menubar.menu(Config.menu_name, 0);

            if (Archetypes.text_editable) {
                var edit_text = (try menu.item("&Edit Text...")).shortcut(.@"return", null).help("Edits the " ++ Config.name ++ "'s text");
                if (edit_text.chosen())
                    try self.startTextEdit();
            }

            if (@hasDecl(Config, "addToMenu"))
                try Config.addToMenu(self, menu);

            if (!Archetypes.dialog) {
                if (menu.impl.menu_items_at > 0)
                    try menu.separator();

                var delete = (try menu.item("Delete")).shortcut(.delete, null).help("Deletes the " ++ Config.name);
                if (delete.chosen())
                    self.root.designer.removeDesignControlById(self.id);
            }

            try menu.end();
        }

        fn startTextEdit(self: *Impl) !void {
            std.debug.assert(self.state == .idle);
            std.debug.assert(self.imtui.focused(self.control()));
            self.state = .{ .text_edit = .{} };
            try self.state.text_edit.appendSlice(self.imtui.allocator, self.text.items);
        }

        fn border(self: *const Impl, colour: u8) void {
            switch (Archetypes.sizing) {
                .autosized => self.imtui.text_mode.paintColour(
                    self.dialog.r1 + self.r1,
                    self.dialog.c1 + self.c1,
                    self.dialog.r1 + self.r2,
                    self.dialog.c1 + self.c2,
                    colour,
                    .fill,
                ),
                .width_resizable => self.imtui.text_mode.paintColour(
                    self.dialog.r1 + self.r1,
                    self.dialog.c1 + self.c1,
                    self.dialog.r1 + self.r2,
                    self.dialog.c1 + self.c2,
                    colour,
                    .fill,
                ),
                .wh_resizable => self.imtui.text_mode.paintColour(
                    (if (!Archetypes.dialog) self.dialog.r1 else 0) + self.r1 - 1,
                    (if (!Archetypes.dialog) self.dialog.c1 else 0) + self.c1 - 1,
                    (if (!Archetypes.dialog) self.dialog.r1 else 0) + self.r2 + 1,
                    (if (!Archetypes.dialog) self.dialog.c1 else 0) + self.c2 + 1,
                    colour,
                    .outline,
                ),
            }
        }
    };
}

test {
    const testing = std.testing;

    const Autosized = DesCon(struct {
        pub const behaviours = .{};
    });
    try testing.expectEqualDeep(&[_][]const u8{ "idle", "move" }, std.meta.fieldNames(Autosized.State));
    try testing.expectEqualDeep(&[_][]const u8{ "origin_row", "origin_col" }, std.meta.fieldNames(std.meta.TagPayloadByName(Autosized.State, "move")));

    const WidthResizable = DesCon(struct {
        pub const behaviours = .{.width_resizable};
    });
    try testing.expectEqualDeep(&[_][]const u8{ "idle", "resize", "move" }, std.meta.fieldNames(WidthResizable.State));
    try testing.expectEqualDeep(&[_][]const u8{"end"}, std.meta.fieldNames(std.meta.TagPayloadByName(WidthResizable.State, "resize")));

    const AutosizedTextEditable = DesCon(struct {
        pub const behaviours = .{.text_editable};
    });
    try testing.expectEqualDeep(&[_][]const u8{ "idle", "text_edit", "move" }, std.meta.fieldNames(AutosizedTextEditable.State));
    try testing.expectEqualDeep(&[_][]const u8{ "origin_row", "origin_col", "edit_eligible" }, std.meta.fieldNames(std.meta.TagPayloadByName(AutosizedTextEditable.State, "move")));

    const WhResizableTextEditable = DesCon(struct {
        pub const behaviours = .{ .wh_resizable, .text_editable };
    });
    try testing.expectEqualDeep(&[_][]const u8{ "idle", "resize", "text_edit", "move" }, std.meta.fieldNames(WhResizableTextEditable.State));
    try testing.expectEqualDeep(&[_][]const u8{"cix"}, std.meta.fieldNames(std.meta.TagPayloadByName(WhResizableTextEditable.State, "resize")));
}
