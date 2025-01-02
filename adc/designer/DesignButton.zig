const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignButton = @This();

pub const Impl = DesignBehaviours.Impl(struct {
    pub const name = "button";
    pub const menu_name = "&Button";
    pub const behaviours = .{.text_editable};

    pub const Fields = struct {
        primary: bool,
        cancel: bool,
    };

    pub fn describe(self: *Impl) void {
        const len = Imtui.Controls.lenWithoutAccelerators(self.fields.text.items);
        self.fields.r2 = self.fields.r1 + 1;
        self.fields.c2 = self.fields.c1 + 4 + len;

        const r1 = self.fields.dialog.fields.r1 + self.fields.r1;
        const c1 = self.fields.dialog.fields.c1 + self.fields.c1;
        const r2 = self.fields.dialog.fields.r1 + self.fields.r2;
        const c2 = self.fields.dialog.fields.c1 + self.fields.c2;
        self.fields.text_start = c1 + 2;

        if (self.fields.primary) {
            self.imtui.text_mode.paintColour(r1, c1, r2, c1 + 1, 0x7f, .fill);
            self.imtui.text_mode.paintColour(r1, c2 - 1, r2, c2, 0x7f, .fill);
        }

        self.imtui.text_mode.write(r1, c1, "<");
        self.imtui.text_mode.writeAccelerated(r1, c1 + 2, self.fields.text.items, true);
        self.imtui.text_mode.write(r1, c2 - 1, ">");
    }

    pub fn addToMenu(self: *Impl, menu: Imtui.Controls.Menu) !void {
        var primary = (try menu.item("&Primary")).help("Toggles the button's primary status");
        if (self.fields.primary)
            primary.bullet();
        if (primary.chosen())
            self.fields.primary = !self.fields.primary;

        var cancel = (try menu.item("&Cancel")).help("Toggles the button's cancel status");
        if (self.fields.cancel)
            cancel.bullet();
        if (cancel.chosen())
            self.fields.cancel = !self.fields.cancel;
    }
});

impl: *Impl,

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, id: usize, r1: usize, c1: usize, text: []const u8, primary: bool, cancel: bool) !DesignButton {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .root = root,
        .id = id,
        .fields = .{
            .dialog = dialog,
            .r1 = r1,
            .c1 = c1,
            .text = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, text)),
            .primary = primary,
            .cancel = cancel,
        },
    };
    d.describe();
    return .{ .impl = d };
}

pub const Schema = struct {
    id: usize,
    r1: usize,
    c1: usize,
    text: []const u8,
    primary: bool,
    cancel: bool,

    pub fn deinit(self: Schema, allocator: Allocator) void {
        allocator.free(self.text);
    }

    pub fn bufPrintFocusLabel(self: *const Schema, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "[Button] {s}", .{self.text});
    }
};

pub fn sync(self: DesignButton, allocator: Allocator, schema: *Schema) !void {
    schema.id = self.impl.id;
    schema.r1 = self.impl.fields.r1;
    schema.c1 = self.impl.fields.c1;
    if (!std.mem.eql(u8, schema.text, self.impl.fields.text.items)) {
        allocator.free(schema.text);
        schema.text = try allocator.dupe(u8, self.impl.fields.text.items);
    }
    schema.primary = self.impl.fields.primary;
    schema.cancel = self.impl.fields.cancel;
}
