const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignDialog = @This();

pub const Impl = DesignBehaviours.Impl(struct {
    pub const name = "dialog";
    pub const menu_name = "&Dialog";
    pub const behaviours = .{ .wh_resizable, .text_editable, .dialog };

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

pub fn bufPrintImtuiId(buf: []u8, _: *DesignRoot.Impl, _: usize, _: usize, _: usize, _: usize, _: usize, _: []const u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}", .{"designer.DesignDialog"});
}

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, id: usize, r1: usize, c1: usize, r2: usize, c2: usize, text: []const u8) !DesignDialog {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .root = root,
        .id = id,
        .fields = .{
            .r1 = r1,
            .c1 = c1,
            .r2 = r2,
            .c2 = c2,
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
    r2: usize,
    c2: usize,
    text: []const u8,

    pub fn deinit(self: Schema, allocator: Allocator) void {
        allocator.free(self.text);
    }

    pub fn bufPrintFocusLabel(self: *const Schema, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "[Dialog] {s}", .{self.text});
    }
};

pub fn sync(self: DesignDialog, allocator: Allocator, schema: *Schema) !void {
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
