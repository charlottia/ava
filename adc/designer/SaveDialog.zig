const std = @import("std");
const imtuilib = @import("imtui");

const Imtui = imtuilib.Imtui;
const Designer = @import("./Designer.zig");

const SaveDialog = @This();

// TODO: Windows support!

imtui: *Imtui,
designer: *Designer,
initial_name: ?[]const u8,
cwd: std.fs.Dir,
cwd_name: []u8,
dirs: std.ArrayListUnmanaged([]u8),

fn stringSort(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

pub fn init(designer: *Designer, initial_name: ?[]const u8) !SaveDialog {
    const imtui = designer.imtui;

    var s = SaveDialog{
        .imtui = imtui,
        .designer = designer,
        .initial_name = initial_name,
        .cwd = undefined,
        .cwd_name = undefined,
        .dirs = undefined,
    };
    try s.setCwd(try std.fs.cwd().openDir(".", .{ .iterate = true }));
    return s;
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

pub fn render(self: *SaveDialog) !bool {
    var open = true;

    var dialog = try self.imtui.dialog("Save As", 19, 37, .centred);

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
        open = try self.process(dialog, input.impl.value);
        dirs_drives.impl.selected_ix = 0;
        dirs_drives.impl.selected_ix_focused = false;
        if (open)
            try self.imtui.focus(input.impl.control());
    }

    var cancel = try dialog.button(17, 18, "Cancel");
    cancel.cancel();
    if (cancel.chosen()) {
        self.imtui.unfocus(dialog.impl.control());
        open = false;
    }

    try dialog.end();

    return open;
}

fn process(self: *SaveDialog, dialog: Imtui.Controls.Dialog, input: *std.ArrayListUnmanaged(u8)) !bool {
    if (std.mem.endsWith(u8, input.items, "/")) {
        const new_cwd = try self.cwd.openDir(input.items, .{ .iterate = true });
        self.clearCwd();
        try self.setCwd(new_cwd);

        input.clearRetainingCapacity();
        return true;
    }

    if (input.items.len == 0)
        // TODO: "Must specify name"
        return true;

    const h = self.cwd.createFile(input.items, .{}) catch |e| {
        // TODO: register this somehow
        std.log.debug("failed to open file for writing '{s}': {any}", .{ input.items, e });
        return true;
    };
    {
        defer h.close();
        try self.designer.dump(h.writer());
    }

    if (self.designer.save_filename) |n| {
        self.imtui.allocator.free(n);
        self.designer.save_filename = null;
    }
    self.designer.save_filename = try self.imtui.allocator.dupe(u8, input.items);

    self.imtui.unfocus(dialog.impl.control());
    self.designer.save_confirm_open = true;
    return false;
}
