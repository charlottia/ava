const std = @import("std");
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;
const Designer = @import("./Designer.zig");

const ReorderDialog = @This();

imtui: *Imtui,
designer: *Designer,
ixs: std.ArrayListUnmanaged(usize),
items: std.ArrayListUnmanaged([]const u8),
selected_ix: usize,

pub fn init(designer: *Designer, focused_dc: ?Designer.DesignControl) !ReorderDialog {
    const imtui = designer.imtui;

    var ixs = std.ArrayListUnmanaged(usize){};
    var items = std.ArrayListUnmanaged([]const u8){};
    var selected_ix: usize = 0;

    var buf: [100]u8 = undefined;
    for (designer.controls.items[1..], 1..) |c, ix| {
        try ixs.append(imtui.allocator, ix);
        const item_label = switch (c) {
            inline else => |p, tag| l: {
                if (focused_dc) |f|
                    switch (f) {
                        tag => |d| if (d.impl == p.impl) {
                            selected_ix = ix - 1;
                        },
                        else => {},
                    };
                break :l try p.schema.bufPrintFocusLabel(&buf);
            },
        };
        try items.append(imtui.allocator, try imtui.allocator.dupe(u8, item_label));
    }

    return .{
        .imtui = designer.imtui,
        .designer = designer,
        .ixs = ixs,
        .items = items,
        .selected_ix = selected_ix,
    };
}

pub fn deinit(self: *ReorderDialog) void {
    for (self.items.items) |i|
        self.imtui.allocator.free(i);
    self.items.deinit(self.imtui.allocator);
    self.ixs.deinit(self.imtui.allocator);
}

pub fn render(self: *ReorderDialog) !bool {
    var open = true;

    var dialog = try self.imtui.dialog("designer.ReorderDialog", "Reorder", 20, 47, .centred);

    dialog.label(1, 11, "&Controls");

    var controls = try dialog.select(2, 2, 17, 28, 0x70, self.selected_ix);
    controls.items(self.items.items);
    controls.end();

    const six = controls.impl.selected_ix;

    var move_up = try dialog.button(7, 32, "Move &Up");
    if (move_up.chosen()) {
        if (six > 0) {
            std.mem.swap(usize, &self.ixs.items[six], &self.ixs.items[six - 1]);
            std.mem.swap([]const u8, &self.items.items[six], &self.items.items[six - 1]);
            controls.impl.selected_ix -= 1;
        }
        try self.imtui.focus(controls.impl.control());
    }

    var move_down = try dialog.button(10, 31, "Move &Down");
    if (move_down.chosen()) {
        if (six < self.items.items.len - 1) {
            std.mem.swap(usize, &self.ixs.items[six], &self.ixs.items[six + 1]);
            std.mem.swap([]const u8, &self.items.items[six], &self.items.items[six + 1]);
            controls.impl.selected_ix += 1;
        }
        try self.imtui.focus(controls.impl.control());
    }

    dialog.hrule(17, 0, 47, 0x70);

    var ok = try dialog.button(18, 12, "OK");
    ok.default();
    if (ok.chosen()) {
        var new_controls = try std.ArrayListUnmanaged(Designer.DesignControl).initCapacity(self.imtui.allocator, self.designer.controls.items.len);
        new_controls.appendAssumeCapacity(self.designer.controls.items[0]);
        for (self.ixs.items) |ix|
            new_controls.appendAssumeCapacity(self.designer.controls.items[ix]);
        self.designer.controls.replaceRangeAssumeCapacity(0, self.designer.controls.items.len, new_controls.items);
        new_controls.deinit(self.imtui.allocator);

        self.imtui.unfocus(dialog.impl.control());
        open = false;
    }

    var cancel = try dialog.button(18, 27, "Cancel");
    cancel.cancel();
    if (cancel.chosen()) {
        self.imtui.unfocus(dialog.impl.control());
        open = false;
    }

    try dialog.end();

    return open;
}
