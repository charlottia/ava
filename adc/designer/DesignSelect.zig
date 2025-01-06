const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignBehaviours = @import("./DesignBehaviours.zig");

const DesignSelect = @This();

pub const ITEMS: []const []const u8 = &.{
    // cp437 lets gooooooooooo
    "armadillo",
    "barboleta",
    "cachorro",
    "dromedario",
    "elefante",
    "fring\xA1lido",
    "gato",
    "hormiguita",
    "ibis",
    "jirafa",
    "kiwi",
    "le\xA2n",
    "mono ara\xA4a",
    "\xA4u",
    "oveja",
    "peixe",
    "quetzal",
    "rato",
    "suricata",
    "toro",
    "urub\xA3",
    "vaca",
    "yak",
    "zarig\x81eya",
    "chinchilla",
    "llama",
};

pub const Impl = DesignBehaviours.Impl(struct {
    pub const name = "select";
    pub const menu_name = "&Select";
    pub const behaviours = .{ .wh_resizable, .flood_select };

    pub const Fields = struct {
        horizontal: bool, // TODO: multiple widths
        select_focus: bool,
    };

    pub fn describe(self: *Impl) void {
        const x = self.coords();

        self.imtui.text_mode.box(x.r1, x.c1, x.r2, x.c2, 0x70);

        if (self.fields.horizontal) {
            const width = Imtui.Controls.DialogSelect.HORIZONTAL_WIDTH; // <- usable characters; 1 padding on each side added.

            var r = x.r1;
            var c = x.c1 + 1;
            for (ITEMS, 0..) |n, ix| {
                r += 1;
                if (r == x.r2 - 1) {
                    r = x.r1 + 1;
                    c += width + 2;
                    if (c + width + 3 > x.c2 - 1)
                        break;
                }
                if (!self.fields.select_focus and ix == 19)
                    self.imtui.text_mode.paint(r, c, r + 1, c + width + 3, 0x07, .Blank);
                self.imtui.text_mode.write(r, c + 1, n);
            }

            _ = self.imtui.text_mode.hscrollbar(x.r2 - 1, x.c1 + 1, x.c2 - 1, 0, 0);
        } else {
            for (ITEMS, 0..) |n, ix| {
                const r = x.r1 + 1 + ix;
                if (r == x.r2 - 1) break;
                if (!self.fields.select_focus and ix == 1)
                    self.imtui.text_mode.paint(r, x.c1 + 1, r + 1, x.c2 - 1, 0x07, .Blank);
                self.imtui.text_mode.write(r, x.c1 + 2, n);
            }

            _ = self.imtui.text_mode.vscrollbar(x.c2 - 1, x.r1 + 1, x.r2 - 1, 0, 0);
        }
    }

    pub fn addToMenu(self: *Impl, menu: Imtui.Controls.Menu) !void {
        var horizontal = (try menu.item("&Horizontal")).help("Toggles the select's horizontal mode");
        if (self.fields.horizontal)
            horizontal.bullet();
        if (horizontal.chosen())
            self.fields.horizontal = !self.fields.horizontal;

        var select_focus = (try menu.item("Select &Focus")).help("Toggles the select's focus mode");
        if (self.fields.select_focus)
            select_focus.bullet();
        if (select_focus.chosen())
            self.fields.select_focus = !self.fields.select_focus;
    }
});

impl: *Impl,

pub fn create(imtui: *Imtui, root: *DesignRoot.Impl, dialog: *DesignDialog.Impl, schema: Schema) !DesignSelect {
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
            .horizontal = schema.horizontal,
            .select_focus = schema.select_focus,
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
    horizontal: bool = false,
    select_focus: bool = false,

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
    schema.horizontal = self.impl.fields.horizontal;
    schema.select_focus = self.impl.fields.select_focus;
}
