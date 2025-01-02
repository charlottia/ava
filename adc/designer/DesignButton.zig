const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignButton = @This();

pub const Impl = DesignBehaviours.DesCon(struct {
    pub const name = "button";
    pub const menu_name = "&Button";
    pub const behaviours = .{.text_editable};

    pub fn describe(self: *Impl) void {
        const len = Imtui.Controls.lenWithoutAccelerators(self.text.items);
        self.r2 = self.r1 + 1;
        self.c2 = self.c1 + 4 + len;

        const r1 = self.dialog.r1 + self.r1;
        const c1 = self.dialog.c1 + self.c1;
        const r2 = self.dialog.r1 + self.r2;
        const c2 = self.dialog.c1 + self.c2;
        self.text_start = c1 + 2;

        if (self.primary) {
            self.imtui.text_mode.paintColour(r1, c1, r2, c1 + 1, 0x7f, .fill);
            self.imtui.text_mode.paintColour(r1, c2 - 1, r2, c2, 0x7f, .fill);
        }

        self.imtui.text_mode.write(r1, c1, "<");
        self.imtui.text_mode.writeAccelerated(r1, c1 + 2, self.text.items, true);
        self.imtui.text_mode.write(r1, c2 - 1, ">");
    }
});

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: *DesignRoot.Impl, _: *DesignDialog.Impl, id: usize, _: usize, _: usize, _: []const u8, _: bool, _: bool) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}", .{ "designer.DesignButton", id });
}

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, id: usize, r1: usize, c1: usize, text: []const u8, primary: bool, cancel: bool) !DesignButton {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .root = root,
        .dialog = dialog,
        .id = id,
        .r1 = r1,
        .c1 = c1,
        .r2 = undefined,
        .c2 = undefined,
        .text = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, text)),
        .primary = primary,
        .cancel = cancel,
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
    schema.r1 = self.impl.r1;
    schema.c1 = self.impl.c1;
    if (!std.mem.eql(u8, schema.text, self.impl.text.items)) {
        allocator.free(schema.text);
        schema.text = try allocator.dupe(u8, self.impl.text.items);
    }
    schema.primary = self.impl.primary;
    schema.cancel = self.impl.cancel;
}
