const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignLabel = @This();

pub const Impl = DesignBehaviours.Impl(struct {
    pub const name = "label";
    pub const menu_name = "&Label";
    pub const behaviours = .{.text_editable};

    pub fn describe(self: *Impl) void {
        const len = Imtui.Controls.lenWithoutAccelerators(self.fields.text.items);
        self.fields.r2 = self.fields.r1 + 1;
        self.fields.c2 = self.fields.c1 + len;

        const r1 = self.fields.dialog.fields.r1 + self.fields.r1;
        const c1 = self.fields.dialog.fields.c1 + self.fields.c1;
        self.fields.text_start = c1;

        self.imtui.text_mode.paint(r1, c1, r1 + 1, c1 + len, 0x70, 0);
        self.imtui.text_mode.writeAccelerated(r1, c1, self.fields.text.items, true);
    }
});

impl: *Impl,

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, id: usize, r1: usize, c1: usize, text: []const u8) !DesignLabel {
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
            .c2 = undefined,
            .text = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, text)),
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

    pub fn deinit(self: Schema, allocator: Allocator) void {
        allocator.free(self.text);
    }

    pub fn bufPrintFocusLabel(self: *const Schema, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "[Label] {s}", .{self.text});
    }
};

pub fn sync(self: DesignLabel, allocator: Allocator, schema: *Schema) !void {
    schema.id = self.impl.id;
    schema.r1 = self.impl.fields.r1;
    schema.c1 = self.impl.fields.c1;
    if (!std.mem.eql(u8, schema.text, self.impl.fields.text.items)) {
        allocator.free(schema.text);
        schema.text = try allocator.dupe(u8, self.impl.fields.text.items);
    }
}
