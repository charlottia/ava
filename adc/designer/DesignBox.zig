const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignBox = @This();

pub const Impl = DesignBehaviours.Impl(struct {
    pub const name = "box";
    pub const menu_name = "&Box";
    pub const behaviours = .{ .wh_resizable, .text_editable };

    pub fn describe(self: *Impl) void {
        const x = self.coords();

        self.imtui.text_mode.box(x.r1, x.c1, x.r2, x.c2, 0x70);

        const len = Imtui.Controls.lenWithoutAccelerators(self.fields.text.items);
        if (len > 0) {
            self.fields.text_start = x.c1 + (x.c2 - x.c1 -| len) / 2;
            self.imtui.text_mode.paint(x.r1, self.fields.text_start - 1, x.r1 + 1, self.fields.text_start + len + 1, 0x70, 0);
            self.imtui.text_mode.writeAccelerated(x.r1, self.fields.text_start, self.fields.text.items, true);
        } else self.fields.text_start = x.c1 + (x.c2 - x.c1) / 2;
    }
});

impl: *Impl,

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, schema: Schema) !DesignBox {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .root = root,
        .id = schema.id,
        .fields = .{
            .dialog = dialog,
            .r1 = schema.r1,
            .c1 = schema.c1,
            .r2 = schema.r2,
            .c2 = schema.c2,
            .text = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, schema.text)),
        },
    };
    d.describe();
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
    schema.r1 = self.impl.fields.r1;
    schema.c1 = self.impl.fields.c1;
    schema.r2 = self.impl.fields.r2;
    schema.c2 = self.impl.fields.c2;
    if (!std.mem.eql(u8, schema.text, self.impl.fields.text.items)) {
        allocator.free(schema.text);
        schema.text = try allocator.dupe(u8, self.impl.fields.text.items);
    }
}
