const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignLabel = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    root: *DesignRoot.Impl,
    id: usize,
    dialog: *DesignDialog.Impl,

    // visible state
    r1: usize,
    c1: usize,
    text: std.ArrayListUnmanaged(u8),

    // internal state
    r2: usize = undefined,
    c2: usize = undefined,
    text_orig: std.ArrayListUnmanaged(u8) = .{},

    state: union(enum) {
        idle,
        move: struct {
            origin_row: usize,
            origin_col: usize,
            edit_eligible: bool,
        },
        text_edit,
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

    pub fn describe(self: *Impl, _: *DesignRoot.Impl, _: *DesignDialog.Impl, _: usize, _: usize, _: usize, _: []const u8) void {
        self.r2 = self.r1 + 1;
        self.c2 = self.c1 + self.text.items.len;

        const r1 = self.dialog.r1 + self.r1;
        const c1 = self.dialog.c1 + self.c1;

        self.imtui.text_mode.paint(r1, c1, r1 + 1, c1 + self.text.items.len, 0x70, 0);
        self.imtui.text_mode.write(r1, c1, self.text.items);

        if (!DesignBehaviours.describe_autosized(self)) {
            self.imtui.text_mode.cursor_row = r1;
            self.imtui.text_mode.cursor_col = c1 + self.text.items.len;
            self.imtui.text_mode.cursor_inhibit = false;
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

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));

        if (!try DesignBehaviours.handleKeyPress_autosized(self, keycode, modifiers))
            try DesignBehaviours.handleKeyPress_textEdit(self, keycode, modifiers);
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return DesignBehaviours.isMouseOver_autosized(self);
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return DesignBehaviours.handleMouseDown_autosized(self, b, clicks, cm);
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return DesignBehaviours.handleMouseDrag_autosized(self, b);
    }

    fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return DesignBehaviours.handleMouseUp_autosized(self, b, clicks);
    }

    pub fn adjustRow(self: *Impl, dr: isize) bool {
        return DesignBehaviours.adjustRow(self, 1, self.dialog.r2 - self.dialog.r1 - 1, dr);
    }

    pub fn adjustCol(self: *Impl, dc: isize) bool {
        return DesignBehaviours.adjustCol(self, 1, self.dialog.c2 - self.dialog.c1 - 1, dc);
    }

    pub fn populateHelpLine(self: *Impl, offset: *usize) !void {
        var edit_button = try self.imtui.button(24, offset.*, 0x30, "<Enter=Edit Text>");
        if (edit_button.chosen())
            try DesignBehaviours.startTextEdit(self);
        offset.* += "<Enter=Edit Text> ".len;

        var delete_button = try self.imtui.button(24, offset.*, 0x30, "<Del=Delete>");
        if (delete_button.chosen())
            self.root.designer.removeDesignControlById(self.id);
        offset.* += "<Del=Delete> ".len;
    }

    pub fn createMenu(self: *Impl, menubar: Imtui.Controls.Menubar) !void {
        var menu = try menubar.menu("&Label", 0);

        var edit_label = (try menu.item("&Edit Text...")).shortcut(.@"return", null).help("Edits the label's text");
        if (edit_label.chosen())
            try DesignBehaviours.startTextEdit(self);

        try menu.separator();

        var delete = (try menu.item("Delete")).shortcut(.delete, null).help("Deletes the label");
        if (delete.chosen())
            self.root.designer.removeDesignControlById(self.id);

        try menu.end();
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: *DesignRoot.Impl, _: *DesignDialog.Impl, id: usize, _: usize, _: usize, _: []const u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}", .{ "designer.DesignLabel", id });
}

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, id: usize, r1: usize, c1: usize, text: []const u8) !DesignLabel {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .root = root,
        .dialog = dialog,
        .id = id,
        .r1 = r1,
        .c1 = c1,
        .text = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, text)),
    };
    d.describe(root, dialog, id, r1, c1, text);
    return .{ .impl = d };
}

pub const Schema = struct {
    id: usize,
    r1: usize,
    c1: usize,
    text: []const u8,

    pub fn deinit(self: Schema, allocator: Allocator) void {
        allocator.free(self.text);
    }

    pub fn bufPrintFocusLabel(self: *const Schema, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "[Label] {s}", .{self.text});
    }
};

pub fn sync(self: DesignLabel, allocator: Allocator, schema: *Schema) !void {
    schema.id = self.impl.id;
    schema.r1 = self.impl.r1;
    schema.c1 = self.impl.c1;
    if (!std.mem.eql(u8, schema.text, self.impl.text.items)) {
        allocator.free(schema.text);
        schema.text = try allocator.dupe(u8, self.impl.text.items);
    }
}
