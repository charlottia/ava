const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;
const ini = @import("ini");

const Imtui = imtuilib.Imtui;
const Preferences = ini.Preferences;

const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignButton = @import("./DesignButton.zig");
const DesignInput = @import("./DesignInput.zig");
const DesignRadio = @import("./DesignRadio.zig");
const DesignCheckbox = @import("./DesignCheckbox.zig");
const DesignLabel = @import("./DesignLabel.zig");
const DesignBox = @import("./DesignBox.zig");
const DesignHrule = @import("./DesignHrule.zig");

const Designer = @This();

pub const Prefs = Preferences("net.lottia.textmode-designer", struct {
    system_cursor: bool = false,
});

const DesignControl = union(enum) {
    dialog: struct { schema: DesignDialog.Schema, impl: *DesignDialog.Impl },
    button: struct { schema: DesignButton.Schema, impl: *DesignButton.Impl },
    input: struct { schema: DesignInput.Schema, impl: *DesignInput.Impl },
    radio: struct { schema: DesignRadio.Schema, impl: *DesignRadio.Impl },
    checkbox: struct { schema: DesignCheckbox.Schema, impl: *DesignCheckbox.Impl },
    label: struct { schema: DesignLabel.Schema, impl: *DesignLabel.Impl },
    box: struct { schema: DesignBox.Schema, impl: *DesignBox.Impl },
    hrule: struct { schema: DesignHrule.Schema, impl: *DesignHrule.Impl },

    fn control(self: DesignControl) Imtui.Control {
        return switch (self) {
            inline else => |c| c.impl.control(),
        };
    }

    fn id(self: DesignControl) usize {
        return switch (self) {
            inline else => |p| p.impl.id,
        };
    }

    fn deinit(self: DesignControl, imtui: *Imtui) void {
        switch (self) {
            inline else => |p| p.schema.deinit(imtui.allocator),
        }
    }

    fn informRoot(self: DesignControl) void {
        switch (self) {
            inline else => |p| p.impl.informRoot(),
        }
    }

    fn dump(self: DesignControl, writer: anytype) !void {
        switch (self) {
            inline else => |d| try ini.SerDes(@TypeOf(d.schema), struct {}).save(writer, d.schema),
        }
    }

    fn populateHelpLine(self: DesignControl, offset: *usize) !void {
        return switch (self) {
            inline else => |p| p.impl.populateHelpLine(offset),
        };
    }

    fn createMenu(self: DesignControl, menubar: Imtui.Controls.Menubar) !void {
        return switch (self) {
            inline else => |p| p.impl.createMenu(menubar),
        };
    }
};

const SaveFile = struct {
    underlay: []const u8 = undefined,
};
const SerDes = ini.SerDes(SaveFile, struct {});

imtui: *Imtui,
prefs: Prefs,

save_filename: ?[]const u8,
underlay_filename: []const u8,
underlay_texture: SDL.Texture,
controls: std.ArrayListUnmanaged(DesignControl),

inhibit_underlay: bool = false,
design_root: *DesignRoot.Impl = undefined,
next_focus: ?usize = null,

simulating: bool = false,
simulating_dialog: ?[]const u8 = null,
display: enum { behind, design_only, in_front } = .behind,
save_dialog_open: bool = false,
save_confirm_open: bool = false,

pub fn initDefaultWithUnderlay(imtui: *Imtui, prefs: Prefs, renderer: SDL.Renderer, underlay: []const u8) !Designer {
    const texture = try loadTextureFromFile(imtui.allocator, renderer, underlay);

    var controls = std.ArrayListUnmanaged(DesignControl){};
    try controls.append(imtui.allocator, .{ .dialog = .{
        .schema = .{
            .id = 1,
            .r1 = 5,
            .c1 = 5,
            .r2 = 20,
            .c2 = 60,
            .text = try imtui.allocator.dupe(u8, "Untitled Dialog"),
        },
        .impl = undefined,
    } });

    return .{
        .imtui = imtui,
        .prefs = prefs,
        .save_filename = null,
        .underlay_filename = try imtui.allocator.dupe(u8, underlay),
        .underlay_texture = texture,
        .controls = controls,
    };
}

pub fn initFromIni(imtui: *Imtui, prefs: Prefs, renderer: SDL.Renderer, inifile: []const u8) !Designer {
    const data = try std.fs.cwd().readFileAllocOptions(imtui.allocator, inifile, 10485760, null, @alignOf(u8), 0);
    defer imtui.allocator.free(data);

    var p = ini.Parser.init(data, .report);
    const save_file = try SerDes.loadGroup(imtui.allocator, &p);

    const texture = try loadTextureFromFile(imtui.allocator, renderer, save_file.underlay);
    var controls = std.ArrayListUnmanaged(DesignControl){};

    while (try p.next()) |ev| {
        std.debug.assert(ev == .group);
        var found = false;
        inline for (std.meta.fields(DesignControl)) |f| {
            if (std.mem.eql(u8, ev.group, f.name)) {
                try controls.append(imtui.allocator, @unionInit(
                    DesignControl,
                    f.name,
                    .{
                        .schema = try ini.SerDes(
                            std.meta.fieldInfo(f.type, .schema).type,
                            struct {},
                        ).loadGroup(imtui.allocator, &p),
                        .impl = undefined,
                    },
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
        .prefs = prefs,
        .save_filename = try imtui.allocator.dupe(u8, inifile),
        .underlay_filename = save_file.underlay,
        .underlay_texture = texture,
        .controls = controls,
    };
}

pub fn deinit(self: *Designer) void {
    if (self.simulating_dialog) |text|
        self.imtui.allocator.free(text);
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
        try c.dump(writer);
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
    self.imtui.text_mode.cursor_inhibit = true;

    if (self.simulating) {
        self.inhibit_underlay = true;

        const menubar = try self.renderMenus(null);
        try self.renderHelpLine(null, menubar);
        try self.renderSimulation();
    } else {
        const focused_dc = try self.renderItems();
        const menubar = try self.renderMenus(focused_dc);
        try self.renderHelpLine(focused_dc, menubar);

        self.inhibit_underlay = false;
        if (self.save_dialog_open)
            try self.renderSaveDialog();
        if (self.save_confirm_open)
            try self.renderSaveConfirm();
    }
}

fn renderItems(self: *Designer) !?DesignControl {
    // What a mess!
    var focused: ?DesignControl = null;

    self.design_root = (try self.imtui.getOrPutControl(DesignRoot, .{self})).impl;
    if (self.imtui.focus_stack.items.len == 0) {
        try self.imtui.focus_stack.append(self.imtui.allocator, self.design_root.control());
    } else for (self.controls.items) |i|
        if (self.imtui.focusedAnywhere(i.control())) {
            i.informRoot();
            focused = i;
        };

    const dp = &self.controls.items[0].dialog;
    const dd = try self.imtui.getOrPutControl(DesignDialog, .{
        self.design_root,
        dp.schema.id,
        dp.schema.r1,
        dp.schema.c1,
        dp.schema.r2,
        dp.schema.c2,
        dp.schema.text,
    });
    dp.impl = dd.impl;
    try dd.sync(self.imtui.allocator, &dp.schema);

    for (self.controls.items[1..], 1..) |*i, ix| {
        // TODO: inline else this somehow :)
        switch (i.*) {
            .dialog => unreachable,
            .button => |*p| {
                const b = try self.imtui.getOrPutControl(
                    DesignButton,
                    .{
                        self.design_root,
                        dd.impl,
                        p.schema.id,
                        p.schema.r1,
                        p.schema.c1,
                        p.schema.text,
                        p.schema.default,
                        p.schema.cancel,
                    },
                );
                p.impl = b.impl;
                try b.sync(self.imtui.allocator, &p.schema);
                if (self.next_focus != null and self.next_focus == ix)
                    try self.imtui.focus(b.impl.control());
            },
            .input => |*p| {
                const b = try self.imtui.getOrPutControl(
                    DesignInput,
                    .{
                        self.design_root,
                        dd.impl,
                        p.schema.id,
                        p.schema.r1,
                        p.schema.c1,
                        p.schema.c2,
                    },
                );
                p.impl = b.impl;
                try b.sync(self.imtui.allocator, &p.schema);
                if (self.next_focus != null and self.next_focus == ix)
                    try self.imtui.focus(b.impl.control());
            },
            .radio => |*p| {
                const b = try self.imtui.getOrPutControl(
                    DesignRadio,
                    .{
                        self.design_root,
                        dd.impl,
                        p.schema.id,
                        p.schema.r1,
                        p.schema.c1,
                        p.schema.text,
                    },
                );
                p.impl = b.impl;
                try b.sync(self.imtui.allocator, &p.schema);
                if (self.next_focus != null and self.next_focus == ix)
                    try self.imtui.focus(b.impl.control());
            },
            .checkbox => |*p| {
                const b = try self.imtui.getOrPutControl(
                    DesignCheckbox,
                    .{
                        self.design_root,
                        dd.impl,
                        p.schema.id,
                        p.schema.r1,
                        p.schema.c1,
                        p.schema.text,
                    },
                );
                p.impl = b.impl;
                try b.sync(self.imtui.allocator, &p.schema);
                if (self.next_focus != null and self.next_focus == ix)
                    try self.imtui.focus(b.impl.control());
            },
            .label => |*p| {
                const l = try self.imtui.getOrPutControl(
                    DesignLabel,
                    .{ self.design_root, dd.impl, p.schema.id, p.schema.r1, p.schema.c1, p.schema.text },
                );
                p.impl = l.impl;
                try l.sync(self.imtui.allocator, &p.schema);
                if (self.next_focus != null and self.next_focus == ix)
                    try self.imtui.focus(l.impl.control());
            },
            .box => |*p| {
                const l = try self.imtui.getOrPutControl(
                    DesignBox,
                    .{
                        self.design_root,
                        dd.impl,
                        p.schema.id,
                        p.schema.r1,
                        p.schema.c1,
                        p.schema.r2,
                        p.schema.c2,
                        p.schema.text,
                    },
                );
                p.impl = l.impl;
                try l.sync(self.imtui.allocator, &p.schema);
                if (self.next_focus != null and self.next_focus == ix)
                    try self.imtui.focus(l.impl.control());
            },
            .hrule => |*p| {
                const l = try self.imtui.getOrPutControl(
                    DesignHrule,
                    .{ self.design_root, dd.impl, p.schema.id, p.schema.r1, p.schema.c1, p.schema.c2 },
                );
                p.impl = l.impl;
                try l.sync(self.imtui.allocator, &p.schema);
                if (self.next_focus != null and self.next_focus == ix)
                    try self.imtui.focus(l.impl.control());
            },
        }
    }

    self.next_focus = null;

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

    var view_menu = try menubar.menu("&View", 0);

    var simulate = (try view_menu.item("&Simulate")).shortcut(.f5, null).help("Simulates the dialog design");
    if (simulate.chosen())
        // TODO: assert dialog has at least one focusable, since Dialogs
        // themselves don't receive focus.
        self.simulating = true;

    try view_menu.separator();

    var underlay = (try view_menu.item("&Underlay")).shortcut(.grave, null).help("Cycles the underlay between behind, in front, and hidden");
    if (underlay.chosen())
        self.display = switch (self.display) {
            .behind => .in_front,
            .in_front => .design_only,
            .design_only => .behind,
        };

    var system_cursor = (try view_menu.item("System &Cursor")).help("Toggles showing the system cursor");
    if (self.prefs.settings.system_cursor)
        system_cursor.bullet();
    if (system_cursor.chosen()) {
        self.prefs.settings.system_cursor = !self.prefs.settings.system_cursor;
        _ = try SDL.showCursor(self.prefs.settings.system_cursor);
        try self.prefs.save();
    }

    try view_menu.end();

    var add_menu = try menubar.menu("&Add", 16);

    var button = (try add_menu.item("&Button")).help("Adds new button to dialog");
    if (button.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .button = .{
            .schema = .{
                .id = self.nextDesignControlId(),
                .r1 = 5,
                .c1 = 5,
                .text = try self.imtui.allocator.dupe(u8, "OK"),
                .default = false,
                .cancel = false,
            },
            .impl = undefined,
        } });
        self.next_focus = self.controls.items.len - 1;
    }

    var input = (try add_menu.item("&Input")).help("Adds new input to dialog");
    if (input.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .input = .{
            .schema = .{
                .id = self.nextDesignControlId(),
                .r1 = 5,
                .c1 = 5,
                .c2 = 10,
            },
            .impl = undefined,
        } });
        self.next_focus = self.controls.items.len - 1;
    }

    var radio = (try add_menu.item("&Radio")).help("Adds new radio to dialog");
    if (radio.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .radio = .{
            .schema = .{
                .id = self.nextDesignControlId(),
                .r1 = 5,
                .c1 = 5,
                .text = try self.imtui.allocator.dupe(u8, "Dogll"),
            },
            .impl = undefined,
        } });
        self.next_focus = self.controls.items.len - 1;
    }

    var checkbox = (try add_menu.item("&Checkbox")).help("Adds new checkbox to dialog");
    if (checkbox.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .checkbox = .{
            .schema = .{
                .id = self.nextDesignControlId(),
                .r1 = 5,
                .c1 = 5,
                .text = try self.imtui.allocator.dupe(u8, "Dogll"),
            },
            .impl = undefined,
        } });
        self.next_focus = self.controls.items.len - 1;
    }

    try add_menu.separator();

    var label = (try add_menu.item("&Label")).help("Adds new label to dialog");
    if (label.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .label = .{
            .schema = .{
                .id = self.nextDesignControlId(),
                .r1 = 5,
                .c1 = 5,
                .text = try self.imtui.allocator.dupe(u8, "Awawa"),
            },
            .impl = undefined,
        } });
        self.next_focus = self.controls.items.len - 1;
    }

    var box = (try add_menu.item("Bo&x")).help("Adds new box to dialog");
    if (box.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .box = .{
            .schema = .{
                .id = self.nextDesignControlId(),
                .r1 = 3,
                .c1 = 3,
                .r2 = 7,
                .c2 = 7,
                .text = try self.imtui.allocator.dupe(u8, "Awawa"),
            },
            .impl = undefined,
        } });
        self.next_focus = self.controls.items.len - 1;
    }

    var hrule = (try add_menu.item("&Hrule")).help("Adds new hrule to dialog");
    if (hrule.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .hrule = .{
            .schema = .{
                .id = self.nextDesignControlId(),
                .r1 = 5,
                .c1 = 5,
                .c2 = 10,
            },
            .impl = undefined,
        } });
        self.next_focus = self.controls.items.len - 1;
    }

    try add_menu.end();

    var controls_menu = try menubar.menu("&Controls", 0);
    var buf: [100]u8 = undefined;
    for (self.controls.items) |c|
        switch (c) {
            inline else => |p, tag| {
                // XXX: This is awkwardly placed in the schema because brand new
                // controls will have impl=undefined at this point. Do better.
                const item_label = try p.schema.bufPrintFocusLabel(&buf);
                var item = (try controls_menu.item(item_label)).help("Focuses " ++ @tagName(tag));
                if (focused_dc) |f|
                    switch (f) {
                        tag => |d| if (d.impl == p.impl)
                            item.bullet(),
                        else => {},
                    };
                if (item.chosen())
                    try self.imtui.focus(p.impl.control());
            },
        };
    try controls_menu.end();

    if (focused_dc) |f|
        try f.createMenu(menubar);

    if (builtin.mode == .Debug) {
        var debug_menu = try menubar.menu("Debu&g", 0);

        var dump_ids = (try debug_menu.item("&Dump All IDs")).shortcut(.d, .ctrl).help("Dumps all Imtui IDs to stderr");
        if (dump_ids.chosen()) {
            std.log.debug("dumping ids", .{});
            var it = self.imtui.controls.keyIterator();
            while (it.next()) |t|
                std.log.debug("  {s}", .{t.*});
        }

        try debug_menu.end();
    }

    menubar.end();

    return menubar;
}

fn renderHelpLine(self: *Designer, focused_dc: ?DesignControl, menubar: Imtui.Controls.Menubar) !void {
    self.imtui.text_mode.paint(24, 0, 25, 80, 0x30, .Blank);

    const focused = self.imtui.focus_stack.getLast();
    if (focused.is(Imtui.Controls.Menubar.Impl)) |mb| {
        if (mb.focus != null and mb.focus.? == .menu) {
            const help_text = menubar.itemAt(mb.focus.?.menu).help.?;
            self.imtui.text_mode.write(24, 1, help_text);
            return;
        } else if (mb.focus != null and mb.focus.? == .menubar) {
            self.imtui.text_mode.write(24, 1, "Enter=Display Menu   Esc=Cancel   Arrow=Next Item");
            return;
        }
    } else if (focused.parent()) |p|
        if (p.is(Imtui.Controls.Dialog.Impl)) |_| {
            self.imtui.text_mode.write(24, 1, "Enter=Execute   Esc=Cancel   Tab=Next Field   Arrow=Next Item");
            return;
        };

    if (self.design_root.editing_text) {
        self.imtui.text_mode.write(24, 1, "Enter=Execute   Esc=Cancel");
        return;
    }

    if (focused_dc) |f| {
        var offset: usize = 1;

        try f.populateHelpLine(&offset);

        std.debug.assert(offset <= 44);
        offset = 45;
        self.imtui.text_mode.write(24, 45, "Arrows=Move  Tab=Next  Esc=Unfocus");
        var next_shortcut = try self.imtui.shortcut(.tab, null);
        if (next_shortcut.chosen())
            try self.nextDesignControl(f);
        var prev_shortcut = try self.imtui.shortcut(.tab, .shift);
        if (prev_shortcut.chosen())
            try self.prevDesignControl(f);

        var unfocus_shortcut = try self.imtui.shortcut(.escape, null);
        if (unfocus_shortcut.chosen())
            self.imtui.unfocus(f.control());
    } else {
        var next_button = try self.imtui.button(24, 61, 0x30, "<Tab=Focus Dialog>");
        var next_shortcut = try self.imtui.shortcut(.tab, null);
        if (next_button.chosen() or next_shortcut.chosen())
            try self.imtui.focus(self.controls.items[0].control());
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

    dialog.hrule(4, 0, 40, 0x70);

    var ok = try dialog.button(5, 17, "OK");
    ok.default();
    if (ok.chosen()) {
        self.save_confirm_open = false;
        self.imtui.unfocus(dialog.impl.control());
    }

    try dialog.end();
}

fn renderSimulation(self: *Designer) !void {
    self.imtui.text_mode.cursor_inhibit = false;

    const dp = &self.controls.items[0].dialog;

    var dialog = try self.imtui.dialog(dp.schema.text, dp.schema.r2 - dp.schema.r1, dp.schema.c2 - dp.schema.c1, .centred);

    var rid: usize = 0;

    for (self.controls.items[1..]) |i| {
        switch (i) {
            .dialog => unreachable,
            .button => |p| {
                const b = try dialog.button(p.schema.r1, p.schema.c1, p.schema.text);
                if (p.schema.default)
                    b.default();
                if (p.schema.cancel)
                    b.cancel();
                if (b.chosen())
                    self.simulating_dialog = try std.fmt.allocPrint(self.imtui.allocator, "\"{s}\" button pressed.", .{p.schema.text});
            },
            .input => |p| _ = try dialog.input(p.schema.r1, p.schema.c1, p.schema.c2),
            .radio => |p| {
                _ = try dialog.radio(0, rid, p.schema.r1, p.schema.c1, p.schema.text);
                rid += 1;
            },
            .checkbox => |p| _ = try dialog.checkbox(p.schema.r1, p.schema.c1, p.schema.text, false),
            .label => |p| dialog.label(p.schema.r1, p.schema.c1, p.schema.text),
            .box => |p| dialog.groupbox(p.schema.text, p.schema.r1, p.schema.c1, p.schema.r2, p.schema.c2, 0x70),
            .hrule => |p| dialog.hrule(p.schema.r1, p.schema.c1, p.schema.c2, 0x70),
        }
    }

    try dialog.end();

    if (self.simulating_dialog) |msg| {
        var confirm_dialog = try self.imtui.dialog("", 7, 40, .centred);

        self.imtui.text_mode.write(confirm_dialog.impl.r1 + 2, confirm_dialog.impl.c1 + (confirm_dialog.impl.c2 - confirm_dialog.impl.c1 - msg.len) / 2, msg);

        confirm_dialog.hrule(4, 0, 40, 0x70);

        var ok = try confirm_dialog.button(5, 17, "OK");
        ok.default();

        try confirm_dialog.end();

        // Ensure we clear the focus stack after drawing the dialog, thus
        // causing regeneration of all impls. Bit of a HACK but it works.
        if (ok.chosen()) {
            self.imtui.allocator.free(msg);
            self.simulating_dialog = null;
            self.simulating = false;
            self.imtui.unfocus(confirm_dialog.impl.control());
            self.imtui.unfocus(dialog.impl.control());
            self.imtui.focus_stack.clearRetainingCapacity();
        }
    }
}

fn nextDesignControlId(self: *const Designer) usize {
    var max: usize = 0;
    for (self.controls.items) |c|
        max = @max(max, c.id());
    return max + 1;
}

fn removeDesignControl(self: *Designer, dc: DesignControl) void {
    self.removeDesignControlById(dc.id());
}

pub fn removeDesignControlById(self: *Designer, id: usize) void {
    const ix = self.findDesignControlIxById(id);
    const dc = self.controls.items[ix];
    self.imtui.unfocus(dc.control());
    _ = self.controls.orderedRemove(ix);
    dc.deinit(self.imtui);
}

fn nextDesignControl(self: *Designer, dc: DesignControl) !void {
    self.imtui.unfocus(dc.control());
    const ix = self.findDesignControlIxById(dc.id());
    try self.imtui.focus(self.controls.items[(ix + 1) % self.controls.items.len].control());
}

fn prevDesignControl(self: *Designer, dc: DesignControl) !void {
    self.imtui.unfocus(dc.control());
    const ix = self.findDesignControlIxById(dc.id());
    const prev: usize = if (ix == 0) self.controls.items.len - 1 else ix - 1;
    try self.imtui.focus(self.controls.items[prev].control());
}

fn findDesignControlIxById(self: *const Designer, id: usize) usize {
    for (self.controls.items, 0..) |c, i|
        if (c.id() == id)
            return i;

    unreachable;
}
