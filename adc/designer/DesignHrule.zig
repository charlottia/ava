const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignHrule = @This();

pub const Impl = DesignBehaviours.Impl(struct {
    pub const name = "hrule";
    pub const menu_name = "&Hrule";
    pub const behaviours = .{.width_resizable};

    pub fn describe(self: *Impl) void {
        self.fields.r2 = self.fields.r1 + 1;

        const x = self.coords();
        self.imtui.text_mode.paint(x.r1, x.c1, x.r2, x.c2, 0x70, .Horizontal);
        if (self.fields.c1 == 0)
            self.imtui.text_mode.draw(x.r1, x.c1, 0x70, .VerticalRight);
        if (self.fields.c2 == self.fields.dialog.fields.c2 - self.fields.dialog.fields.c1)
            self.imtui.text_mode.draw(x.r1, x.c2 - 1, 0x70, .VerticalLeft);
    }
});

impl: *Impl,

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, schema: Schema) !DesignHrule {
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
            .c2 = schema.c2,
        },
    };
    d.describe();
    return .{ .impl = d };
}

pub const Schema = struct {
    id: usize,
    r1: usize,
    c1: usize,
    c2: usize,

    pub fn deinit(_: Schema, _: Allocator) void {}

    pub fn bufPrintFocusLabel(_: *const Schema, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "[Hrule]", .{});
    }
};

pub fn sync(self: DesignHrule, _: Allocator, schema: *Schema) !void {
    schema.id = self.impl.id;
    schema.r1 = self.impl.fields.r1;
    schema.c1 = self.impl.fields.c1;
    schema.c2 = self.impl.fields.c2;
}
