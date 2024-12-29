const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;
const ini = @import("ini");

const Imtui = imtuilib.Imtui;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignButton = @import("./DesignButton.zig");
const DesignLabel = @import("./DesignLabel.zig");

const Designer = @This();

const DesignControl = union(enum) {
    dialog: struct { ix: usize, schema: DesignDialog.Schema, impl: *DesignDialog.Impl },
    button: struct { ix: usize, schema: DesignButton.Schema, impl: *DesignButton.Impl },
    label: struct { ix: usize, schema: DesignLabel.Schema, impl: *DesignLabel.Impl },

    // XXX: use this more below?
    fn control(self: DesignControl) Imtui.Control {
        return switch (self) {
            inline else => |c| c.impl.control(),
        };
    }

    fn ix(self: DesignControl) usize {
        return switch (self) {
            inline else => |p| p.ix,
        };
    }

    fn deinit(self: DesignControl, imtui: *Imtui) void {
        switch (self) {
            inline else => |p| p.schema.deinit(imtui.allocator),
        }
    }
};

const SaveFile = struct {
    underlay: []const u8 = undefined,
};
const SerDes = ini.SerDes(SaveFile, struct {});

imtui: *Imtui,
save_filename: ?[]const u8,
underlay_filename: []const u8,
underlay_texture: SDL.Texture,
controls: std.ArrayListUnmanaged(DesignControl),

inhibit_underlay: bool = false,

design_root: *DesignRoot.Impl = undefined,
display: enum { behind, design_only, in_front } = .behind,
save_dialog_open: bool = false,
save_confirm_open: bool = false,

pub fn initDefaultWithUnderlay(imtui: *Imtui, renderer: SDL.Renderer, underlay: []const u8) !Designer {
    const texture = try loadTextureFromFile(imtui.allocator, renderer, underlay);

    var controls = std.ArrayListUnmanaged(DesignControl){};
    try controls.append(imtui.allocator, .{ .dialog = .{
        .ix = 0,
        .schema = .{
            .r1 = 5,
            .c1 = 5,
            .r2 = 20,
            .c2 = 60,
            .title = try imtui.allocator.dupe(u8, "Untitled Dialog"),
        },
        .impl = undefined,
    } });

    return .{
        .imtui = imtui,
        .save_filename = null,
        .underlay_filename = try imtui.allocator.dupe(u8, underlay),
        .underlay_texture = texture,
        .controls = controls,
    };
}

pub fn initFromIni(imtui: *Imtui, renderer: SDL.Renderer, inifile: []const u8) !Designer {
    const data = try std.fs.cwd().readFileAllocOptions(imtui.allocator, inifile, 10485760, null, @alignOf(u8), 0);
    defer imtui.allocator.free(data);

    var p = ini.Parser.init(data, .report);
    const save_file = try SerDes.loadGroup(imtui.allocator, &p);

    const texture = try loadTextureFromFile(imtui.allocator, renderer, save_file.underlay);
    var controls = std.ArrayListUnmanaged(DesignControl){};

    var ix: usize = 0;

    while (try p.next()) |ev| {
        std.debug.assert(ev == .group);
        var found = false;
        inline for (std.meta.fields(DesignControl)) |f| {
            if (std.mem.eql(u8, ev.group, f.name)) {
                try controls.append(imtui.allocator, @unionInit(
                    DesignControl,
                    f.name,
                    .{
                        .ix = ix,
                        .schema = try ini.SerDes(
                            std.meta.fieldInfo(f.type, .schema).type,
                            struct {},
                        ).loadGroup(imtui.allocator, &p),
                        .impl = undefined,
                    },
                ));
                ix += 1;
                found = true;
                break;
            }
        }
        if (!found)
            std.debug.panic("unknown group '{s}'", .{ev.group});
    }

    return .{
        .imtui = imtui,
        .save_filename = try imtui.allocator.dupe(u8, inifile),
        .underlay_filename = save_file.underlay,
        .underlay_texture = texture,
        .controls = controls,
    };
}

pub fn deinit(self: *Designer) void {
    for (self.controls.items) |c|
        c.deinit(self.imtui);
    self.controls.deinit(self.imtui.allocator);
    self.underlay_texture.destroy();
    self.imtui.allocator.free(self.underlay_filename);
    if (self.save_filename) |f| self.imtui.allocator.free(f);
}

pub fn dump(self: *const Designer, writer: anytype) !void {
    try SerDes.save(writer, .{ .underlay = self.underlay_filename });

    for (self.controls.items) |c| {
        try std.fmt.format(writer, "\n[{s}]\n", .{@tagName(c)});
        switch (c) {
            inline else => |d| try ini.SerDes(@TypeOf(d), struct {}).save(writer, d),
        }
    }
}

fn loadTextureFromFile(allocator: Allocator, renderer: SDL.Renderer, filename: []const u8) !SDL.Texture {
    const data = try std.fs.cwd().readFileAllocOptions(allocator, filename, 10485760, null, @alignOf(u8), 0);
    defer allocator.free(data);
    const texture = try SDL.image.loadTextureMem(renderer, data, .png);
    try texture.setAlphaMod(128);
    try texture.setBlendMode(.blend);
    return texture;
}

pub fn render(self: *Designer) !void {
    const focused_dc = try self.renderItems();
    const menubar = try self.renderMenus(focused_dc);
    try self.renderHelpLine(focused_dc, menubar);

    self.inhibit_underlay = false;
    if (self.save_dialog_open)
        try self.renderSaveDialog();
    if (self.save_confirm_open)
        try self.renderSaveConfirm();
}

fn renderItems(self: *Designer) !?DesignControl {
    // What a mess!

    self.design_root = (try self.imtui.getOrPutControl(DesignRoot, .{})).impl;
    if (self.imtui.focus_stack.items.len == 0)
        try self.imtui.focus_stack.append(self.imtui.allocator, self.design_root.control());

    var focused: ?DesignControl = null;

    const dp = &self.controls.items[0].dialog;
    const dd = try self.imtui.getOrPutControl(DesignDialog, .{
        self.design_root,
        dp.schema.r1,
        dp.schema.c1,
        dp.schema.r2,
        dp.schema.c2,
        dp.schema.title,
    });
    dp.impl = dd.impl;
    try dd.sync(self.imtui.allocator, &dp.schema);
    if (self.imtui.focusedAnywhere(dd.impl.control()))
        focused = self.controls.items[0];

    for (self.controls.items[1..]) |*i| {
        switch (i.*) {
            .dialog => unreachable,
            .button => |*p| {
                const b = try self.imtui.getOrPutControl(
                    DesignButton,
                    .{
                        self.design_root,
                        dd.impl,
                        p.ix,
                        p.schema.r1,
                        p.schema.c1,
                        p.schema.label,
                        p.schema.primary,
                        p.schema.cancel,
                    },
                );
                p.impl = b.impl;
                try b.sync(self.imtui.allocator, &p.schema);
                focused = focused orelse if (self.imtui.focusedAnywhere(b.impl.control())) i.* else null;
            },
            .label => |*p| {
                const l = try self.imtui.getOrPutControl(
                    DesignLabel,
                    .{ self.design_root, dd.impl, p.ix, p.schema.r1, p.schema.c1, p.schema.text },
                );
                p.impl = l.impl;
                try l.sync(self.imtui.allocator, &p.schema);
                focused = focused orelse if (self.imtui.focusedAnywhere(l.impl.control())) i.* else null;
            },
        }
    }

    return focused;
}

fn renderMenus(self: *Designer, focused_dc: ?DesignControl) !Imtui.Controls.Menubar {
    var menubar = try self.imtui.menubar(0, 0, 80);

    var file_menu = try menubar.menu("&File", 16);
    _ = (try file_menu.item("&New Dialog")).help("Removes currently loaded dialog from memory");
    _ = (try file_menu.item("&Open Dialog...")).help("Loads new dialog into memory");
    var save = (try file_menu.item("&Save")).shortcut(.s, .ctrl).help("Writes current dialog to file on disk");
    if (save.chosen()) {
        if (self.save_filename) |f| {
            const h = try std.fs.cwd().createFile(f, .{});
            defer h.close();

            try self.dump(h.writer());

            self.save_confirm_open = true;
        } else {
            self.save_dialog_open = true;
        }
    }
    _ = (try file_menu.item("Save &As...")).help("Saves current dialog with specified name");
    try file_menu.separator();
    var exit = (try file_menu.item("E&xit")).help("Exits Designer and returns to OS");
    if (exit.chosen())
        self.imtui.running = false;
    try file_menu.end();

    var add_menu = try menubar.menu("&Add", 16);
    // TODO: focus new items on add.
    var button = (try add_menu.item("&Button")).help("Adds new button to dialog");
    if (button.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .button = .{
            .ix = self.nextDesignControlIx(),
            .schema = .{
                .r1 = 5,
                .c1 = 5,
                .label = try self.imtui.allocator.dupe(u8, "OK"),
                .primary = false,
                .cancel = false,
            },
            .impl = undefined,
        } });
    }
    var label = (try add_menu.item("&Label")).help("Adds new label to dialog");
    if (label.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .label = .{
            .ix = self.nextDesignControlIx(),
            .schema = .{
                .r1 = 5,
                .c1 = 5,
                .text = try self.imtui.allocator.dupe(u8, "Awawa"),
            },
            .impl = undefined,
        } });
    }
    try add_menu.end();

    var controls_menu = try menubar.menu("&Controls", 16);
    var buf: [100]u8 = undefined;
    for (self.controls.items) |c| {
        switch (c) {
            .dialog => |d| {
                const item_label = try std.fmt.bufPrint(&buf, "[Dialog] {s}", .{d.schema.title});
                var item = (try controls_menu.item(item_label)).help("Focuses dialog");
                if (focused_dc != null and focused_dc.? == .dialog and focused_dc.?.dialog.impl == d.impl)
                    item.bullet();
                if (item.chosen())
                    try self.imtui.focus(d.impl.control());
            },
            .button => |b| {
                const item_label = try std.fmt.bufPrint(&buf, "[Button] {s}", .{b.schema.label});
                var item = (try controls_menu.item(item_label)).help("Focuses button");
                if (focused_dc != null and focused_dc.? == .button and focused_dc.?.button.impl == b.impl)
                    item.bullet();
                if (item.chosen())
                    try self.imtui.focus(b.impl.control());
            },
            .label => |l| {
                const item_label = try std.fmt.bufPrint(&buf, "[Label] {s}", .{l.schema.text});
                var item = (try controls_menu.item(item_label)).help("Focuses label");
                if (focused_dc != null and focused_dc.? == .label and focused_dc.?.label.impl == l.impl)
                    item.bullet();
                if (item.chosen())
                    try self.imtui.focus(l.impl.control());
            },
        }
    }
    try controls_menu.end();

    menubar.end();

    return menubar;
}

fn renderHelpLine(self: *Designer, focused_dc: ?DesignControl, menubar: Imtui.Controls.Menubar) !void {
    const help_line_colour = 0x30;
    self.imtui.text_mode.paint(24, 0, 25, 80, help_line_colour, .Blank);

    var handled = false;

    const focused = self.imtui.focus_stack.getLast();
    if (focused.is(Imtui.Controls.Menubar.Impl)) |mb| {
        if (mb.focus != null and mb.focus.? == .menu) {
            const help_text = menubar.itemAt(mb.focus.?.menu).help.?;
            self.imtui.text_mode.write(24, 1, help_text);
            handled = true;
        } else if (mb.focus != null and mb.focus.? == .menubar) {
            self.imtui.text_mode.write(24, 1, "Enter=Display Menu   Esc=Cancel   Arrow=Next Item");
            handled = true;
        }
    } else if (focused.parent()) |p|
        if (p.is(Imtui.Controls.Dialog.Impl)) |_| {
            self.imtui.text_mode.write(24, 1, "Enter=Execute   Esc=Cancel   Tab=Next Field   Arrow=Next Item");
            handled = true;
        };

    if (!handled and self.design_root.editing_text) {
        self.imtui.text_mode.write(24, 1, "Enter=Execute   Esc=Cancel");
        handled = true;
    }

    if (!handled) {
        var underlay_button = try self.imtui.button(24, 1, help_line_colour, "<`=Underlay>");
        var underlay_shortcut = try self.imtui.shortcut(.grave, null);
        if (underlay_button.chosen() or underlay_shortcut.chosen()) {
            self.display = switch (self.display) {
                .behind => .in_front,
                .in_front => .design_only,
                .design_only => .behind,
            };
        }

        self.imtui.text_mode.draw(24, 14, help_line_colour, .Vertical);
        var offset: usize = 16;

        if (focused_dc) |f| {
            switch (f) {
                .dialog => |d| {
                    // TODO: change when dialog state != idle. (Editing title -> Enter no longer Edit Title)
                    var edit_button = try self.imtui.button(24, offset, help_line_colour, "<Enter=Edit Title>");
                    var edit_shortcut = try self.imtui.shortcut(.@"return", null);
                    if (edit_button.chosen() or edit_shortcut.chosen())
                        try d.impl.startTitleEdit();
                    offset += "<Enter=Edit Title> ".len;
                },
                .button => |b| {
                    // TODO: as above.
                    var edit_button = try self.imtui.button(24, offset, help_line_colour, "<Enter=Edit Label>");
                    var edit_shortcut = try self.imtui.shortcut(.@"return", null);
                    if (edit_button.chosen() or edit_shortcut.chosen())
                        try b.impl.startLabelEdit();
                    offset += "<Enter=Edit Label> ".len;

                    var delete_button = try self.imtui.button(24, offset, help_line_colour, "<Del=Delete>");
                    var delete_shortcut = try self.imtui.shortcut(.delete, null);
                    if (delete_button.chosen() or delete_shortcut.chosen())
                        self.removeDesignControl(f);
                    offset += "<Del=Delete> ".len;
                },
                .label => |l| {
                    // TODO: as above.
                    var edit_button = try self.imtui.button(24, offset, help_line_colour, "<Enter=Edit Text>");
                    var edit_shortcut = try self.imtui.shortcut(.@"return", null);
                    if (edit_button.chosen() or edit_shortcut.chosen())
                        try l.impl.startTextEdit();
                    offset += "<Enter=Edit Text> ".len;

                    var delete_button = try self.imtui.button(24, offset, help_line_colour, "<Del=Delete>");
                    var delete_shortcut = try self.imtui.shortcut(.delete, null);
                    if (delete_button.chosen() or delete_shortcut.chosen())
                        self.removeDesignControl(f);
                    offset += "<Del=Delete> ".len;
                },
            }

            std.debug.assert(offset <= 55);
            offset = 55;
            var next_button = try self.imtui.button(24, offset, help_line_colour, "<Tab=Next>");
            var next_shortcut = try self.imtui.shortcut(.tab, null);
            if (next_button.chosen() or next_shortcut.chosen())
                try self.nextDesignControl(f);
            offset += "<Tab=Next> ".len;
            var prev_shortcut = try self.imtui.shortcut(.tab, .shift);
            if (prev_shortcut.chosen())
                try self.prevDesignControl(f);

            var unfocus_button = try self.imtui.button(24, offset, help_line_colour, "<Esc=Unfocus>");
            var unfocus_shortcut = try self.imtui.shortcut(.escape, null);
            if (unfocus_button.chosen() or unfocus_shortcut.chosen())
                self.imtui.unfocus(f.control());
            offset += "<Esc=Unfocus> ".len;
        } else {
            var next_button = try self.imtui.button(24, offset, help_line_colour, "<Tab=Focus Dialog>");
            var next_shortcut = try self.imtui.shortcut(.tab, null);
            if (next_button.chosen() or next_shortcut.chosen())
                try self.imtui.focus(self.controls.items[0].control());
            offset += "<Tab=Focus Dialog> ".len;
        }
    }
}

fn dialogPrep(self: *Designer) void {
    self.inhibit_underlay = true;
    self.imtui.text_mode.cursor_inhibit = false;
    for (0..self.imtui.text_mode.H) |r|
        for (0..self.imtui.text_mode.W) |c|
            self.imtui.text_mode.shadow(r, c);
}

fn renderSaveDialog(self: *Designer) !void {
    self.dialogPrep();

    var dialog = try self.imtui.dialog("Save As", 10, 60, .centred);

    dialog.groupbox("", 1, 1, 4, 30, 0x70);

    var input = try dialog.input(2, 2, 40);
    if (input.initial()) |init|
        try init.appendSlice(self.imtui.allocator, "dialog.ini");

    var ok = try dialog.button(4, 4, "OK");
    ok.default();
    if (ok.chosen()) {
        self.save_filename = try self.imtui.allocator.dupe(u8, input.impl.value.items);
        const h = try std.fs.cwd().createFile(input.impl.value.items, .{});
        defer h.close();

        try self.dump(h.writer());

        self.save_dialog_open = false;
        self.imtui.unfocus(dialog.impl.control());

        self.save_confirm_open = true;
    }

    var cancel = try dialog.button(4, 30, "Cancel");
    cancel.cancel();
    if (cancel.chosen()) {
        self.save_dialog_open = false;
        self.imtui.unfocus(dialog.impl.control());
    }

    try dialog.end();
}

fn renderSaveConfirm(self: *Designer) !void {
    self.dialogPrep();

    var dialog = try self.imtui.dialog("", 7, 40, .centred);

    var buf: [100]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "Saved to \"{s}\".", .{self.save_filename.?});
    self.imtui.text_mode.write(dialog.impl.r1 + 2, dialog.impl.c1 + (dialog.impl.c2 - dialog.impl.c1 - msg.len) / 2, msg);

    self.imtui.text_mode.draw(dialog.impl.r1 + 4, dialog.impl.c1, 0x70, .VerticalRight);
    self.imtui.text_mode.paint(dialog.impl.r1 + 4, dialog.impl.c1 + 1, dialog.impl.r1 + 4 + 1, dialog.impl.c1 + 40 - 1, 0x70, .Horizontal);
    self.imtui.text_mode.draw(dialog.impl.r1 + 4, dialog.impl.c1 + 40 - 1, 0x70, .VerticalLeft);

    var ok = try dialog.button(5, 17, "OK");
    ok.default();
    if (ok.chosen()) {
        self.save_confirm_open = false;
        self.imtui.unfocus(dialog.impl.control());
    }

    try dialog.end();
}

fn nextDesignControlIx(self: *const Designer) usize {
    var max: usize = 0;
    for (self.controls.items) |c|
        max = @max(max, c.ix());
    return max + 1;
}

fn removeDesignControl(self: *Designer, dc: DesignControl) void {
    self.imtui.unfocus(dc.control());
    const i = self.findDesignControlIndex(dc);
    _ = self.controls.orderedRemove(i);
    dc.deinit(self.imtui);
}

fn nextDesignControl(self: *Designer, dc: DesignControl) !void {
    self.imtui.unfocus(dc.control());
    const i = self.findDesignControlIndex(dc);
    try self.imtui.focus(self.controls.items[(i + 1) % self.controls.items.len].control());
}

fn prevDesignControl(self: *Designer, dc: DesignControl) !void {
    self.imtui.unfocus(dc.control());
    const i = self.findDesignControlIndex(dc);
    const prev: usize = if (i == 0) self.controls.items.len - 1 else i - 1;
    try self.imtui.focus(self.controls.items[prev].control());
}

fn findDesignControlIndex(self: *const Designer, dc: DesignControl) usize {
    const ix = dc.ix();
    for (self.controls.items, 0..) |c, i|
        if (c.ix() == ix)
            return i;

    unreachable;
}
