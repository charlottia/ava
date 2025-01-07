const std = @import("std");
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;
const Designer = @import("./Designer.zig");

pub fn WithTag(comptime Tag_: type) type {
    return struct {
        const UnsavedDialog = @This();

        pub const Result = enum { save, discard, cancel };
        pub const Tag = Tag_;

        imtui: *Imtui,
        tag: Tag,
        finished: ?Result = null,
        rendered: Imtui.Controls.Dialog = undefined,

        pub fn init(designer: *Designer, tag: Tag) UnsavedDialog {
            return .{ .imtui = designer.imtui, .tag = tag };
        }

        pub fn finish(self: *UnsavedDialog, tag: Tag) ?Result {
            if (self.tag != tag)
                return null;

            const result = self.finished orelse return null;
            self.imtui.unfocus(self.rendered.impl.control());
            return result;
        }

        pub fn render(self: *UnsavedDialog) !void {
            var dialog = try self.imtui.dialog("", 7, 60, .centred);
            self.rendered = dialog;

            dialog.label(2, 3, "One or more loaded files are not saved. Save them now?");

            dialog.hrule(4, 0, 60, 0x70);

            var yes = try dialog.button(5, 15, "&Yes");
            yes.default();
            if (yes.chosen())
                self.finished = .save;

            var no = try dialog.button(5, 25, "&No");
            no.padding(2);
            if (no.chosen())
                self.finished = .discard;

            var cancel = try dialog.button(5, 36, "Cancel");
            cancel.cancel();
            cancel.padding(0);
            if (cancel.chosen())
                self.finished = .cancel;

            try dialog.end();
        }
    };
}
