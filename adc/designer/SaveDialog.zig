const std = @import("std");
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;
const Designer = @import("./Designer.zig");

pub fn WithTag(comptime Tag_: type) type {
    return struct {
        const SaveDialog = @This();

        pub const Result = enum { saved, canceled };
        pub const Tag = Tag_;

        // TODO: Windows support!

        imtui: *Imtui,
        designer: *Designer,
        tag: Tag,
        initial_name: ?[]const u8,
        cwd: std.fs.Dir = undefined,
        cwd_name: []u8 = undefined,
        dirs: std.ArrayListUnmanaged([]u8) = undefined,
        finished: ?Result = null,
        rendered: Imtui.Controls.Dialog = undefined,

        fn stringSort(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }

        pub fn init(designer: *Designer, tag: Tag, initial_name: ?[]const u8) !SaveDialog {
            const imtui = designer.imtui;

            var d = SaveDialog{
                .imtui = imtui,
                .designer = designer,
                .tag = tag,
                .initial_name = initial_name,
            };
            try d.setCwd(try std.fs.cwd().openDir(".", .{ .iterate = true }));
            return d;
        }

        fn setCwd(self: *SaveDialog, cwd: std.fs.Dir) !void {
            self.cwd = cwd;
            self.cwd_name = try self.cwd.realpathAlloc(self.imtui.allocator, ".");

            self.dirs = std.ArrayListUnmanaged([]u8){};
            if (!std.mem.eql(u8, self.cwd_name, "/"))
                try self.dirs.append(self.imtui.allocator, try self.imtui.allocator.dupe(u8, ".."));

            var it = self.cwd.iterate();
            while (try it.next()) |e|
                if (e.kind == .directory and !std.mem.startsWith(u8, e.name, ".")) {
                    try self.dirs.append(self.imtui.allocator, try self.imtui.allocator.dupe(u8, e.name));
                };

            std.sort.heap([]u8, self.dirs.items, {}, stringSort);
        }

        fn clearCwd(self: *SaveDialog) void {
            for (self.dirs.items) |i|
                self.imtui.allocator.free(i);
            self.dirs.deinit(self.imtui.allocator);
            self.imtui.allocator.free(self.cwd_name);
            self.cwd.close();
        }

        pub fn deinit(self: *SaveDialog) void {
            self.clearCwd();
        }

        pub fn finish(self: *SaveDialog, tag: Tag) ?Result {
            if (self.tag != tag)
                return null;

            const result = self.finished orelse return null;
            self.imtui.unfocus(self.rendered.impl.control());
            self.deinit();
            return result;
        }

        pub fn render(self: *SaveDialog) !void {
            const title = switch (self.tag) {
                .save => "Save",
                .save_as => "Save As",
                else => "",
            };
            var dialog = try self.imtui.dialog("designer.SaveDialog", title, 19, 37, .centred);
            self.rendered = dialog;

            dialog.label(2, 2, "File &Name:");

            dialog.groupbox("", 1, 13, 4, 35, 0x70);

            var input = try dialog.input(2, 14, 34);
            if (input.initial()) |i|
                try i.appendSlice(self.imtui.allocator, self.initial_name orelse "dialog.ini");

            dialog.label(4, 2, self.cwd_name);

            dialog.label(6, 13, "&Dirs/Drives");

            var dirs_drives = try dialog.select(7, 7, 16, 30, 0x70, 0);
            dirs_drives.items(self.dirs.items);
            dirs_drives.select_focus();
            dirs_drives.end();

            if (dirs_drives.changed()) |v| {
                input.impl.value.clearRetainingCapacity();
                try std.fmt.format(
                    input.impl.value.writer(self.imtui.allocator),
                    "{s}/",
                    .{self.dirs.items[v]},
                );
            }

            dialog.hrule(16, 0, 37, 0x70);

            var ok = try dialog.button(17, 9, "OK");
            ok.default();
            if (ok.chosen()) {
                if (std.mem.endsWith(u8, input.impl.value.items, "/")) {
                    const new_cwd = try self.cwd.openDir(input.impl.value.items, .{ .iterate = true });
                    self.clearCwd();
                    try self.setCwd(new_cwd);

                    input.impl.value.clearRetainingCapacity();
                    dirs_drives.impl.selected_ix = 0;
                    dirs_drives.impl.selected_ix_focused = false;
                    try self.imtui.focus(input.impl.control());
                } else if (input.impl.value.items.len == 0) {
                    // TODO: "Must specify name"
                } else {
                    try self.process(input.impl.value.items);
                    self.finished = .saved;
                }
            }

            var cancel = try dialog.button(17, 18, "Cancel");
            cancel.cancel();
            if (cancel.chosen())
                self.finished = .canceled;

            try dialog.end();
        }

        fn process(self: *SaveDialog, filename: []const u8) !void {
            const h = self.cwd.createFile(filename, .{}) catch |e| {
                // TODO: dialog and don't mark as saved
                std.log.warn("failed to open file for writing '{s}': {any}", .{ filename, e });
                return;
            };
            {
                defer h.close();
                try self.designer.dump(h.writer());
            }

            // TODO: saving path stuff properly here and in Designer
            if (self.designer.save_filename) |n| {
                self.imtui.allocator.free(n);
                self.designer.save_filename = null;
            }
            self.designer.save_filename = try self.imtui.allocator.dupe(u8, filename);
        }
    };
}
