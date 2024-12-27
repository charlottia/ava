const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;
const ini = @import("ini");

const Imtui = imtuilib.Imtui;

const DesignDialog = @import("./DesignDialog.zig");
const DesignButton = @import("./DesignButton.zig");

const Designer = @This();

const Control = union(enum) {
    dialog: DesignDialog.Schema,
    button: DesignButton.Schema,
};

const SaveFile = struct {
    underlay: []const u8 = undefined,
};
const SerDes = ini.SerDes(SaveFile, struct {});

imtui: *Imtui,
save_filename: ?[]const u8,
underlay_filename: []const u8,
underlay_texture: SDL.Texture,
controls: std.ArrayListUnmanaged(Control),

inhibit_underlay: bool = false,

display: enum { behind, design_only, in_front } = .behind,
save_dialog_open: bool = false,
save_confirm_open: bool = false,

pub fn initDefaultWithUnderlay(imtui: *Imtui, renderer: SDL.Renderer, underlay: []const u8) !Designer {
    const texture = try loadTextureFromFile(imtui.allocator, renderer, underlay);

    var controls = std.ArrayListUnmanaged(Control){};
    try controls.append(imtui.allocator, .{ .dialog = .{
        .r1 = 5,
        .c1 = 5,
        .r2 = 20,
        .c2 = 60,
        .title = try imtui.allocator.dupe(u8, "Untitled Dialog"),
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
    var controls = std.ArrayListUnmanaged(Control){};

    while (try p.next()) |ev| {
        std.debug.assert(ev == .group);
        var found = false;
        inline for (std.meta.fields(Control)) |f| {
            if (std.mem.eql(u8, ev.group, f.name)) {
                try controls.append(imtui.allocator, @unionInit(
                    Control,
                    f.name,
                    try ini.SerDes(f.type, struct {}).loadGroup(imtui.allocator, &p),
                ));
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
        switch (c) {
            inline else => |d| d.deinit(self.imtui.allocator),
        };
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
    try self.renderItems();
    const menubar = try self.renderMenus();
    try self.renderHelpLine(menubar);

    self.inhibit_underlay = false;
    if (self.save_dialog_open)
        try self.renderSaveDialog();
    if (self.save_confirm_open)
        try self.renderSaveConfirm();
}

fn renderItems(self: *Designer) !void {
    for (self.controls.items, 0..) |*i, ix| {
        switch (i.*) {
            .dialog => |*s| {
                const dd = try self.imtui.getOrPutControl(DesignDialog, .{ s.r1, s.c1, s.r2, s.c2, s.title });
                if (self.imtui.focus_stack.items.len == 0)
                    try self.imtui.focus_stack.append(self.imtui.allocator, dd.impl.control());
                try dd.sync(self.imtui.allocator, s);
            },
            .button => |*s| {
                const db = try self.imtui.getOrPutControl(DesignButton, .{ ix, s.r, s.c, s.label });
                _ = db;
            },
        }
    }
}

fn renderMenus(self: *Designer) !Imtui.Controls.Menubar {
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
    var exit = (try file_menu.item("E&xit")).help("Exits Designer and returns to DOS");
    if (exit.chosen())
        self.imtui.running = false;
    file_menu.end();

    var add_menu = try menubar.menu("&Add", 16);
    var button = (try add_menu.item("&Button")).help("Add new button to dialog");
    if (button.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .button = .{ .r = 5, .c = 5, .label = try self.imtui.allocator.dupe(u8, "OK") } });
    }
    add_menu.end();

    var controls_menu = try menubar.menu("&Controls", 16);
    for (self.controls.items) |c| {
        switch (c) {
            .dialog => |_| {
                _ = (try controls_menu.item("[Dialog] ")).help("Open dialog properties");
            },
            .button => |_| {
                _ = (try controls_menu.item("[Button] ")).help("Open button properties");
            },
        }
    }
    controls_menu.end();

    menubar.end();

    return menubar;
}

fn renderHelpLine(self: *Designer, menubar: Imtui.Controls.Menubar) !void {
    const help_line_colour = 0x30;
    self.imtui.text_mode.paint(24, 0, 25, 80, help_line_colour, .Blank);

    var show_ruler = true;
    var handled = false;

    const focused = self.imtui.focus_stack.getLast();
    if (focused.is(Imtui.Controls.Menubar.Impl)) |mb| {
        if (mb.focus != null and mb.focus.? == .menu) {
            const help_text = menubar.itemAt(mb.focus.?.menu).help.?;
            self.imtui.text_mode.write(24, 1, "F1=Help");
            self.imtui.text_mode.draw(24, 9, help_line_colour, .Vertical);
            self.imtui.text_mode.write(24, 11, help_text);
            show_ruler = (11 + help_text.len) <= 62;
            handled = true;
        } else if (mb.focus != null and mb.focus.? == .menubar) {
            self.imtui.text_mode.write(24, 1, "Enter=Display Menu   Esc=Cancel   Arrow=Next Item");
            handled = true;
        }
    } else if (focused.parent()) |p|
        if (p.is(Imtui.Controls.Dialog.Impl)) |_| {
            self.imtui.text_mode.write(24, 1, "Enter=Execute   Esc=Cancel   Tab=Next Field   Arrow=Next Item");
            show_ruler = false;
            handled = true;
        };

    if (!handled) {
        var underlay_button = try self.imtui.button(24, 1, help_line_colour, "<`=Underlay>");
        var underlay_shortcut = try self.imtui.shortcut(.grave, null);
        if (underlay_button.chosen() or underlay_shortcut.chosen()) {
            self.display = switch (self.display) {
                .behind => .design_only,
                .design_only => .in_front,
                .in_front => .behind,
            };
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
