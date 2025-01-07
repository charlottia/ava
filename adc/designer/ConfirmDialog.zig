const std = @import("std");
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;
const Designer = @import("./Designer.zig");

pub fn WithTag(comptime Tag: type) type {
    return struct {
        const ConfirmDialog = @This();

        comptime Tag: type = Tag,

        imtui: *Imtui,
        tag: Tag,
        title: []u8,
        text: []u8,
        finished: bool = false,
        rendered: Imtui.Controls.Dialog = undefined,

        pub fn init(designer: *Designer, tag: Tag, title: []const u8, comptime fmt: []const u8, args: anytype) !ConfirmDialog {
            const imtui = designer.imtui;

            return .{
                .imtui = imtui,
                .tag = tag,
                .title = try imtui.allocator.dupe(u8, title),
                .text = try std.fmt.allocPrint(imtui.allocator, fmt, args),
            };
        }

        pub fn deinit(self: *ConfirmDialog) void {
            self.imtui.allocator.free(self.text);
            self.imtui.allocator.free(self.title);
        }

        pub fn finish(self: *ConfirmDialog, tag: Tag) bool {
            if (self.tag != tag or !self.finished)
                return false;

            self.imtui.unfocus(self.rendered.impl.control());
            self.deinit();
            return true;
        }

        pub fn render(self: *ConfirmDialog) !void {
            const w = @max(self.text.len + 6, 12);

            var dialog = try self.imtui.dialog(self.title, 7, w, .centred);
            self.rendered = dialog;

            self.imtui.text_mode.write(
                dialog.impl.r1 + 2,
                dialog.impl.c1 + (dialog.impl.c2 - dialog.impl.c1 - self.text.len) / 2,
                self.text,
            );

            dialog.hrule(4, 0, w, 0x70);

            var ok = try dialog.button(5, (w - 8) / 2, "OK");
            ok.padding(2);
            ok.default();
            if (ok.chosen())
                self.finished = true;

            try dialog.end();
        }
    };
}
