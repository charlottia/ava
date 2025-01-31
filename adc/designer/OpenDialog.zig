const std = @import("std");
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;
const Designer = @import("./Designer.zig");

pub fn WithTag(comptime Tag_: type) type {
    return struct {
        const OpenDialog = @This();

        pub const Result = union(enum) {
            opened: []u8,
            canceled,
        };
        pub const Tag = Tag_;

        // TODO: Windows support!

        imtui: *Imtui,
        designer: *Designer,
        tag: Tag,
        filter: []u8,
        cwd: std.fs.Dir = undefined,
        cwd_name: []u8 = undefined,
        files: std.ArrayListUnmanaged([]u8) = undefined,
        dirs: std.ArrayListUnmanaged([]u8) = undefined,
        finished: ?Result = null,
        rendered: Imtui.Controls.Dialog = undefined,

        fn stringSort(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }

        pub fn init(designer: *Designer, tag: Tag, ext: ?[]const u8) !OpenDialog {
            const imtui = designer.imtui;

            var d = OpenDialog{
                .imtui = imtui,
                .designer = designer,
                .tag = tag,
                .filter = if (ext) |e|
                    try std.fmt.allocPrint(imtui.allocator, "*.{s}", .{e})
                else
                    try imtui.allocator.dupe(u8, "*.*"),
            };
            try d.setCwd(try std.fs.cwd().openDir(".", .{ .iterate = true }));
            return d;
        }

        fn setCwd(self: *OpenDialog, cwd: std.fs.Dir) !void {
            std.debug.assert(std.mem.startsWith(u8, self.filter, "*."));

            self.cwd = cwd;
            self.cwd_name = try self.cwd.realpathAlloc(self.imtui.allocator, ".");

            self.files = std.ArrayListUnmanaged([]u8){};
            self.dirs = std.ArrayListUnmanaged([]u8){};
            if (!std.mem.eql(u8, self.cwd_name, "/"))
                try self.dirs.append(self.imtui.allocator, try self.imtui.allocator.dupe(u8, ".."));

            var it = self.cwd.iterate();
            while (try it.next()) |e| {
                if (std.mem.startsWith(u8, e.name, "."))
                    continue;
                if (e.kind == .directory) {
                    try self.dirs.append(self.imtui.allocator, try self.imtui.allocator.dupe(u8, e.name));
                } else if (e.kind == .file) {
                    if (std.mem.eql(u8, self.filter, "*.*") or std.ascii.endsWithIgnoreCase(e.name, self.filter[1..]))
                        try self.files.append(self.imtui.allocator, try self.imtui.allocator.dupe(u8, e.name));
                }
            }

            std.sort.heap([]u8, self.files.items, {}, stringSort);
            std.sort.heap([]u8, self.dirs.items, {}, stringSort);
        }

        fn clearCwd(self: *OpenDialog) void {
            for (self.dirs.items) |i|
                self.imtui.allocator.free(i);
            self.dirs.deinit(self.imtui.allocator);
            for (self.files.items) |i|
                self.imtui.allocator.free(i);
            self.files.deinit(self.imtui.allocator);
            self.imtui.allocator.free(self.cwd_name);
            self.cwd.close();
        }

        pub fn deinit(self: *OpenDialog) void {
            self.clearCwd();
            self.imtui.allocator.free(self.filter);
        }

        pub fn finish(self: *OpenDialog, tag: Tag) ?Result {
            if (self.tag != tag)
                return null;

            const result = self.finished orelse return null;
            self.imtui.unfocus(self.rendered.impl.control());
            self.deinit();
            return result;
        }

        pub fn render(self: *OpenDialog) !void {
            var dialog = try self.imtui.dialog("designer.OpenDialog", "Open Dialog", 21, 67, .centred);
            self.rendered = dialog;

            dialog.label(2, 2, "File &Name:");

            dialog.groupbox("", 1, 13, 4, 65, 0x70);

            var input = try dialog.input(2, 14, 64);
            if (input.initial()) |v|
                try v.appendSlice(self.imtui.allocator, self.filter);

            dialog.label(5, 2, self.cwd_name);

            dialog.label(6, 22, "&Files");

            var files = try dialog.select(7, 2, 18, 47, 0x70, 0);
            files.items(self.files.items);
            files.select_focus();
            files.horizontal();
            files.end();

            if (files.changed()) |v| {
                try input.impl.value.replaceRange(
                    self.imtui.allocator,
                    0,
                    input.impl.value.items.len,
                    self.files.items[v],
                );
                input.impl.el.cursor_col = self.files.items[v].len;
            }

            dialog.label(6, 51, "&Dirs/Drives");

            var dirs_drives = try dialog.select(7, 49, 18, 65, 0x70, 0);
            dirs_drives.items(self.dirs.items);
            dirs_drives.select_focus();
            dirs_drives.end();

            if (dirs_drives.changed()) |v| {
                input.impl.value.clearRetainingCapacity();
                try std.fmt.format(
                    input.impl.value.writer(self.imtui.allocator),
                    "{s}/{s}",
                    .{ self.dirs.items[v], self.filter },
                );
            }

            dialog.hrule(18, 0, 67, 0x70);

            var ok = try dialog.button(19, 21, "OK");
            ok.default();
            if (ok.chosen()) {
                // TODO: openDir fails abort the program etc.
                if (std.mem.indexOf(u8, input.impl.value.items, "*.") != null) {
                    if (std.mem.lastIndexOfScalar(u8, input.impl.value.items, '/')) |fs| {
                        self.imtui.allocator.free(self.filter);
                        self.filter = try self.imtui.allocator.dupe(u8, input.impl.value.items[fs + 1 ..]);

                        const new_cwd = try self.cwd.openDir(input.impl.value.items[0..fs], .{ .iterate = true });
                        self.clearCwd();
                        try self.setCwd(new_cwd);
                    } else {
                        self.imtui.allocator.free(self.filter);
                        self.filter = try self.imtui.allocator.dupe(u8, input.impl.value.items);

                        const cwd = try self.cwd.openDir(".", .{ .iterate = true });
                        self.clearCwd();
                        try self.setCwd(cwd);
                    }

                    input.impl.value.replaceRangeAssumeCapacity(0, input.impl.value.items.len, self.filter);
                    input.impl.el.cursor_col = self.filter.len;
                    files.impl.selected_ix = 0;
                    files.impl.selected_ix_focused = false;
                    dirs_drives.impl.selected_ix = 0;
                    dirs_drives.impl.selected_ix_focused = false;
                    try self.imtui.focus(input.impl.control());
                } else if (input.impl.value.items.len == 0) {
                    self.designer.confirm_dialog = try Designer.ConfirmDialog.init(self.designer, .open_dialog, "", "Must specify name", .{});
                } else if (self.cwd.realpathAlloc(self.imtui.allocator, input.impl.value.items)) |path| {
                    self.finished = .{ .opened = path };
                } else |err| {
                    self.designer.confirm_dialog = try Designer.ConfirmDialog.init(self.designer, .open_dialog, "", "Error opening '{s}': {any}", .{ input.impl.value.items, err });
                }
            }

            var cancel = try dialog.button(19, 35, "Cancel");
            cancel.cancel();
            if (cancel.chosen())
                self.finished = .canceled;

            try dialog.end();

            if (self.designer.confirm_dialog) |*cd| if (cd.finish(.open_dialog)) {
                self.designer.confirm_dialog = null;
            };
        }
    };
}
