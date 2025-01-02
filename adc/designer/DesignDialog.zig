const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignDialog = @This();

pub const Impl = DesignBehaviours.DesCon(struct {
    pub const name = "dialog";
    pub const menu_name = "&Dialog";
    pub const behaviours = .{ .wh_resizable, .text_editable, .dialog };

    pub fn describe(self: *Impl) void {
        const r1 = self.r1;
        const c1 = self.c1;
        const r2 = self.r2;
        const c2 = self.c2;

        self.imtui.text_mode.box(r1, c1, r2, c2, 0x70);

        const len = Imtui.Controls.lenWithoutAccelerators(self.text.items);
        if (len > 0) {
            self.text_start = c1 + (c2 - c1 -| len) / 2;
            self.imtui.text_mode.paint(r1, self.text_start - 1, r1 + 1, self.text_start + len + 1, 0x70, 0);
            self.imtui.text_mode.writeAccelerated(r1, self.text_start, self.text.items, true);
        } else self.text_start = c1 + (c2 - c1) / 2;
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
        .r1 = r1,
        .c1 = c1,
        .r2 = r2,
        .c2 = c2,
        .text = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, text)),
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
    schema.r1 = self.impl.r1;
    schema.c1 = self.impl.c1;
    schema.r2 = self.impl.r2;
    schema.c2 = self.impl.c2;
    if (!std.mem.eql(u8, schema.text, self.impl.text.items)) {
        allocator.free(schema.text);
        schema.text = try allocator.dupe(u8, self.impl.text.items);
    }
}
