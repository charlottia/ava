const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignInput = @This();

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
        const c1 = self.dialog.c1 + self.c1;
        const c2 = self.dialog.c1 + self.c2;

        for (c1..c2) |c|
            self.imtui.text_mode.write(r1, c, ".");

        DesignBehaviours.describe_widthResizable(self);
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
        return DesignBehaviours.handleKeyPress_widthResizable(self, keycode, modifiers);
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return DesignBehaviours.isMouseOver_widthResizable(self);
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return DesignBehaviours.handleMouseDown_widthResizable(self, b, clicks, cm);
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return DesignBehaviours.handleMouseDrag_widthResizable(self, b);
    }

    fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return DesignBehaviours.handleMouseUp_widthResizable(self, b, clicks);
    }

    pub fn adjustRow(self: *Impl, dr: isize) bool {
        return DesignBehaviours.adjustRow(self, 1, self.dialog.r2 - self.dialog.r1 - 1, dr);
    }

    pub fn adjustCol(self: *Impl, dc: isize) bool {
        return DesignBehaviours.adjustCol(self, 1, self.dialog.c2 - self.dialog.c1 - 1, dc);
    }

    pub fn populateHelpLine(self: *Impl, offset: *usize) !void {
        var delete_button = try self.imtui.button(24, offset.*, 0x30, "<Del=Delete>");
        if (delete_button.chosen())
            self.root.designer.removeDesignControlById(self.id);
        offset.* += "<Del=Delete> ".len;
    }

    pub fn createMenu(self: *Impl, menubar: Imtui.Controls.Menubar) !void {
        var menu = try menubar.menu("&Input", 0);

        var delete = (try menu.item("Delete")).shortcut(.delete, null).help("Deletes the input");
        if (delete.chosen())
            self.root.designer.removeDesignControlById(self.id);

        try menu.end();
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: *DesignRoot.Impl, _: *DesignDialog.Impl, id: usize, _: usize, _: usize, _: usize) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}", .{ "designer.DesignInput", id });
}

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, id: usize, r1: usize, c1: usize, c2: usize) !DesignInput {
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

    pub fn bufPrintFocusLabel(_: *const Schema, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "[Input]", .{});
    }
};

pub fn sync(self: DesignInput, _: Allocator, schema: *Schema) !void {
    schema.id = self.impl.id;
    schema.r1 = self.impl.r1;
    schema.c1 = self.impl.c1;
    schema.c2 = self.impl.c2;
}
