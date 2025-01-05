const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignSelect = @This();

pub const Impl = DesignBehaviours.Impl(struct {
    pub const name = "select";
    pub const menu_name = "&Select";
    pub const behaviours = .{.wh_resizable};

    const ITEMS: []const []const u8 = &.{ "armadillo", "barboleta", "cachorro" };

    pub fn describe(self: *Impl) void {
        const x = self.coords();

        self.imtui.text_mode.box(x.r1, x.c1, x.r2, x.c2, 0x70);

        for (ITEMS, 0..) |n, ix| {
            const r = x.r1 + 1 + ix;
            if (r == x.r2 - 1) break;
            if (ix == 1)
                self.imtui.text_mode.paint(r, x.c1 + 1, r + 1, x.c2 - 1, 0x07, .Blank);
            self.imtui.text_mode.write(r, x.c1 + 2, n);
        }

        _ = self.imtui.text_mode.vscrollbar(x.c2 - 1, x.r1 + 1, x.r2 - 1, 0, 0);
    }
});

impl: *Impl,

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, id: usize, r1: usize, c1: usize, r2: usize, c2: usize) !DesignSelect {
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
            .r2 = r2,
            .c2 = c2,
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

    pub fn deinit(_: Schema, _: Allocator) void {}

    pub fn bufPrintFocusLabel(_: *const Schema, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "[Select]", .{});
    }
};

pub fn sync(self: DesignSelect, _: Allocator, schema: *Schema) !void {
    schema.id = self.impl.id;
    schema.r1 = self.impl.fields.r1;
    schema.c1 = self.impl.fields.c1;
    schema.r2 = self.impl.fields.r2;
    schema.c2 = self.impl.fields.c2;
}
