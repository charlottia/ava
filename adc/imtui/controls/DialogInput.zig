const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const EditorLike = @import("./EditorLike.zig");
const Source = @import("./Source.zig");
const Imtui = @import("../Imtui.zig");

const DialogInput = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    dialog: *Dialog.Impl,

    // id
    ix: usize,

    // config
    r: usize = undefined,
    c1: usize = undefined,
    c2: usize = undefined,

    // state
    el: EditorLike,
    source: *Source,
    value: *std.ArrayListUnmanaged(u8), // points straight into `source.lines`
    accel: ?u8 = undefined,
    initted: bool = false,
    changed: bool = false,

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
                .onFocus = onFocus,
                .onBlur = onBlur,
            },
        };
    }

    pub fn describe(self: *Impl, _: *Dialog.Impl, _: usize, r: usize, c1: usize, c2: usize) void {
        self.r = self.dialog.r1 + r;
        self.c1 = self.dialog.c1 + c1;
        self.c2 = self.dialog.c1 + c2;
        self.accel = self.dialog.pendingAccel();

        self.el.describe(self.r, self.c1, self.r + 1, self.c2);
        self.el.draw(self.imtui.focused(self.control()), 0x07);
    }

    fn parent(ptr: *const anyopaque) ?Imtui.Control {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.dialog.control();
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.source.release();
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

    fn onFocus(ptr: *anyopaque) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.el.cursor_col = self.value.items.len;
        self.el.selection_start = .{
            .cursor_row = 0,
            .cursor_col = 0,
        };
    }

    fn onBlur(ptr: *anyopaque) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.el.cursor_col = 0;
        self.el.selection_start = null;
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        // XXX is this all dialog inputs, or just Display's Tab Stops?
        // Note this is the default MAX_LINE for full-screen editors, less Tab
        // Stops' exact c1 (255 - 48 = 207). Hah.
        // const MAX_LINE = 207; // XXX: unused; fit into EditorLike.

        if (keycode != .tab)
            if (try self.el.handleKeyPress(keycode, modifiers)) {
                self.changed = true;
                return;
            };

        try self.dialog.commonKeyPress(self.ix, keycode, modifiers);
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.imtui.mouse_row == self.r and
            self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        const active = self.imtui.focused(self.control());

        if (!cm) {
            if (!isMouseOver(ptr)) {
                const new = try self.dialog.commonMouseDown(b, clicks, cm);
                if (new != null and new.?.is(Dialog.Impl) == null)
                    try onBlur(ptr);
                return new;
            }
        } else {
            // cm
            if (try self.el.handleMouseDown(active, b, clicks, cm))
                return self.control();
            return null;
        }

        if (try self.el.handleMouseDown(active, b, clicks, cm)) {
            if (!active)
                try self.imtui.focus(self.control())
            else
                // clicking on already selected; set cursor where clicked.
                self.el.cursor_col = self.el.scroll_col + self.imtui.mouse_col - self.c1;

            return self.control();
        }

        return null;
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return self.el.handleMouseDrag(b);
    }

    fn handleMouseUp(_: *anyopaque, _: SDL.MouseButton, _: u8) !void {}
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, dialog: *Dialog.Impl, ix: usize, _: usize, _: usize, _: usize) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{s}/{d}", .{ "core.DialogInput", dialog.ident, ix });
}

pub fn create(imtui: *Imtui, dialog: *Dialog.Impl, ix: usize, r: usize, c1: usize, c2: usize) !DialogInput {
    var source = try Source.createSingleLine(imtui.allocator);
    var b = try imtui.allocator.create(Impl);
    b.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .dialog = dialog,
        .ix = ix,
        .el = .{
            .imtui = imtui,
            .source = source,
        },
        .source = source,
        .value = &source.lines.items[0],
    };
    b.describe(dialog, ix, r, c1, c2);
    try dialog.controls.append(imtui.allocator, b.control());
    return .{ .impl = b };
}

pub fn initial(self: DialogInput) ?*std.ArrayListUnmanaged(u8) {
    if (self.impl.initted) return null;
    self.impl.initted = true;
    return self.impl.value;
}

pub fn changed(self: DialogInput) ?[]const u8 {
    defer self.impl.changed = false;
    return if (self.impl.changed) self.impl.value.items else null;
}
