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
        padding: usize,
        default: bool,
        cancel: bool,
    };

    pub fn describe(self: *Impl) void {
        const len = Imtui.Controls.lenWithoutAccelerators(self.fields.text.items);
        self.fields.r2 = self.fields.r1 + 1;
        self.fields.c2 = self.fields.c1 + 2 + (self.fields.padding * 2) + len;

        const x = self.coords();
        self.fields.text_start = x.c1 + 1 + self.fields.padding;

        if (self.fields.default) {
            self.imtui.text_mode.paintColour(x.r1, x.c1, x.r2, x.c1 + 1, 0x7f, .fill);
            self.imtui.text_mode.paintColour(x.r1, x.c2 - 1, x.r2, x.c2, 0x7f, .fill);
        }

        self.imtui.text_mode.write(x.r1, x.c1, "<");
        self.imtui.text_mode.writeAccelerated(x.r1, x.c1 + 1 + self.fields.padding, self.fields.text.items, true);
        self.imtui.text_mode.write(x.r1, x.c2 - 1, ">");
    }

    pub fn addToMenu(self: *Impl, menu: Imtui.Controls.Menu) !void {
        var default = (try menu.item("&Default")).help("Toggles the button's default status");
        if (self.fields.default)
            default.bullet();
        if (default.chosen())
            self.fields.default = !self.fields.default;

        var cancel = (try menu.item("&Cancel")).help("Toggles the button's cancel status");
        if (self.fields.cancel)
            cancel.bullet();
        if (cancel.chosen())
            self.fields.cancel = !self.fields.cancel;

        var padding_increase = (try menu.item("&Increase Padding")).shortcut(.equals, null).help("Increases the padding around the button's text");
        if (padding_increase.chosen())
            self.fields.padding += 1;

        var padding_decrease = (try menu.item("D&ecrease Padding")).shortcut(.minus, null).help("Decreases the padding around the button's text");
        if (padding_decrease.chosen())
            self.fields.padding -|= 1;
    }
});

impl: *Impl,

pub fn create(
    imtui: *Imtui,
    root: *DesignRoot.Impl,
    dialog: *DesignDialog.Impl,
    id: usize,
    r1: usize,
    c1: usize,
    text: []const u8,
    padding: usize,
    default: bool,
    cancel: bool,
) !DesignButton {
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
            .padding = padding,
            .default = default,
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
    padding: usize = 1,
    default: bool,
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
    schema.padding = self.impl.fields.padding;
    schema.default = self.impl.fields.default;
    schema.cancel = self.impl.fields.cancel;
}
