const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;
const ini = @import("ini");

const Imtui = imtuilib.Imtui;
const Preferences = ini.Preferences;

pub const SaveDialog = @import("./SaveDialog.zig").WithTag(enum { new, save, save_as, open, exit });
const OpenDialog = @import("./OpenDialog.zig");
const ReorderDialog = @import("./ReorderDialog.zig");
pub const ConfirmDialog = @import("./ConfirmDialog.zig").WithTag(enum { new_save, save_save, open_save, simulation_end });
pub const UnsavedDialog = @import("./UnsavedDialog.zig").WithTag(enum { new, open });
const DesignRoot = @import("./DesignRoot.zig");
const DesignDialog = @import("./DesignDialog.zig");
const DesignButton = @import("./DesignButton.zig");
const DesignInput = @import("./DesignInput.zig");
const DesignRadio = @import("./DesignRadio.zig");
const DesignCheckbox = @import("./DesignCheckbox.zig");
const DesignSelect = @import("./DesignSelect.zig");
const DesignLabel = @import("./DesignLabel.zig");
const DesignBox = @import("./DesignBox.zig");
const DesignHrule = @import("./DesignHrule.zig");

const Designer = @This();

pub const Prefs = Preferences("net.lottia.textmode-designer", struct {
    system_cursor: bool = false,
});

const mapping = .{
    .dialog = DesignDialog,
    .button = DesignButton,
    .input = DesignInput,
    .radio = DesignRadio,
    .checkbox = DesignCheckbox,
    .select = DesignSelect,
    .label = DesignLabel,
    .box = DesignBox,
    .hrule = DesignHrule,
};

pub const DesignControl = union(enum) {
    dialog: struct { schema: DesignDialog.Schema, impl: *DesignDialog.Impl },
    button: struct { schema: DesignButton.Schema, impl: *DesignButton.Impl },
    input: struct { schema: DesignInput.Schema, impl: *DesignInput.Impl },
    radio: struct { schema: DesignRadio.Schema, impl: *DesignRadio.Impl },
    checkbox: struct { schema: DesignCheckbox.Schema, impl: *DesignCheckbox.Impl },
    select: struct { schema: DesignSelect.Schema, impl: *DesignSelect.Impl },
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

event: ?union(enum) {
    new,
    open: []u8,
} = null,
save_filename: ?[]const u8, // TODO: need directory here too; SaveDialog has it.
underlay_filename: ?[]const u8,
underlay_texture: ?SDL.Texture,
controls: std.ArrayListUnmanaged(DesignControl),
snapshot: ?[]u8 = null,

inhibit_underlay: bool = false,
design_root: *DesignRoot.Impl = undefined,
next_focus: ?usize = null,

simulating: bool = false,
display: enum { behind, design_only, in_front } = .behind,
save_dialog: ?SaveDialog = null,
open_dialog: ?OpenDialog = null,
pending_open: ?[]u8 = null,
reorder_dialog: ?ReorderDialog = null,
confirm_dialog: ?ConfirmDialog = null,
unsaved_dialog: ?UnsavedDialog = null,

pub fn initDefaultWithUnderlay(imtui: *Imtui, prefs: Prefs, renderer: SDL.Renderer, underlay: ?[]const u8) !Designer {
    const texture = if (underlay) |n| try loadTextureFromFile(imtui.allocator, renderer, n) else null;

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
        .underlay_filename = if (underlay) |n| try imtui.allocator.dupe(u8, n) else null,
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
    if (self.confirm_dialog) |*d|
        d.deinit();
    if (self.reorder_dialog) |*d|
        d.deinit();
    if (self.pending_open) |s|
        self.imtui.allocator.free(s);
    if (self.open_dialog) |*d|
        d.deinit();
    if (self.save_dialog) |*d|
        d.deinit();
    if (self.snapshot) |s|
        self.imtui.allocator.free(s);
    for (self.controls.items) |c|
        c.deinit(self.imtui);
    self.controls.deinit(self.imtui.allocator);
    if (self.underlay_texture) |t| t.destroy();
    if (self.underlay_filename) |n| self.imtui.allocator.free(n);
    if (self.save_filename) |f| self.imtui.allocator.free(f);
    self.imtui.focus_stack.clearRetainingCapacity();
}

pub fn dump(self: *const Designer, writer: anytype) !void {
    try SerDes.save(writer, .{ .underlay = self.underlay_filename orelse "" });

    for (self.controls.items) |c| {
        try std.fmt.format(writer, "\n[{s}]\n", .{@tagName(c)});
        try c.dump(writer);
    }
}

fn dumpAlloc(self: *const Designer) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    try self.dump(buf.writer(self.imtui.allocator));
    return try buf.toOwnedSlice(self.imtui.allocator);
}

fn loadTextureFromFile(allocator: Allocator, renderer: SDL.Renderer, filename: []const u8) !?SDL.Texture {
    if (filename.len == 0)
        return null;
    const data = try std.fs.cwd().readFileAllocOptions(allocator, filename, 10485760, null, @alignOf(u8), 0);
    defer allocator.free(data);
    const texture = try SDL.image.loadTextureMem(renderer, data, .png);
    try texture.setAlphaMod(128);
    try texture.setBlendMode(.blend);
    return texture;
}

pub fn render(self: *Designer) !void {
    if (self.snapshot == null)
        self.snapshot = try self.dumpAlloc();

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

        if (self.save_dialog) |*d| {
            self.dialogPrep();
            try d.render();
        }

        if (self.open_dialog) |*d| {
            self.dialogPrep();
            try d.render();
        }

        if (self.reorder_dialog) |*d| {
            self.dialogPrep();
            if (!try d.render()) {
                d.deinit();
                self.reorder_dialog = null;
            }
        }

        if (self.unsaved_dialog) |*d| {
            self.dialogPrep();
            try d.render();
        }
    }

    if (self.confirm_dialog) |*d| {
        self.dialogPrep();
        try d.render();
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

    for (self.controls.items[1..], 1..) |*i, ix|
        switch (i.*) {
            .dialog => unreachable,
            inline else => |*p, tag| {
                const b = try self.imtui.getOrPutControl(
                    @field(mapping, @tagName(tag)),
                    .{ self.design_root, dd.impl, p.schema },
                );
                p.impl = b.impl;
                try b.sync(self.imtui.allocator, &p.schema);
                if (self.next_focus != null and self.next_focus == ix)
                    try self.imtui.focus(b.impl.control());
            },
        };

    self.next_focus = null;

    return focused;
}

fn renderMenus(self: *Designer, focused_dc: ?DesignControl) !Imtui.Controls.Menubar {
    var menubar = try self.imtui.menubar(0, 0, 80);

    var file_menu = try menubar.menu("&File", 16);

    var new = (try file_menu.item("&New Dialog")).help("Removes currently loaded dialog from memory");
    if (new.chosen())
        if (try self.startUnsaved(.new)) {
            self.event = .new;
        };

    switch (try self.checkUnsaved(.new, .new_save)) {
        .nop => {},
        .action => self.event = .new,
        .cancel => {},
    }

    var open = (try file_menu.item("&Open Dialog...")).help("Loads new dialog into memory");
    if (open.chosen())
        self.open_dialog = try OpenDialog.init(self);

    if (self.open_dialog) |*od| if (od.finish()) |r| {
        self.open_dialog = null;
        switch (r) {
            .opened => |path| {
                if (try self.startUnsaved(.open))
                    self.event = .{ .open = path }
                else
                    self.pending_open = path;
            },
            .canceled => {},
        }
    };

    switch (try self.checkUnsaved(.open, .open_save)) {
        .nop => {},
        .action => {
            self.event = .{ .open = self.pending_open.? };
            self.pending_open = null;
        },
        .cancel => {
            self.imtui.allocator.free(self.pending_open.?);
            self.pending_open = null;
        },
    }

    var save = (try file_menu.item("&Save")).shortcut(.s, .ctrl).help("Writes current dialog to file on disk");
    if (save.chosen())
        try self.startSave(.save, .save_save);

    _ = try self.checkSave(.save, .save_save);

    var save_as = (try file_menu.item("Save &As...")).help("Saves current dialog with specified name");
    if (save_as.chosen())
        self.save_dialog = try SaveDialog.init(self, .save_as, self.save_filename);

    _ = try self.checkSave(.save_as, .save_save);

    try file_menu.separator();

    var export_zig = (try file_menu.item("Export &Zig")).help("Exports current dialog as Zig code to stdout");
    if (export_zig.chosen())
        try self.exportZig();

    try file_menu.separator();

    var exit = (try file_menu.item("E&xit")).help("Exits Designer and returns to OS");
    if (exit.chosen())
        self.imtui.running = false;

    try file_menu.end();

    var view_menu = try menubar.menu("&View", 0);

    var simulate = (try view_menu.item("&Simulate")).shortcut(.f5, null).help("Simulates the dialog design");
    if (!self.designSimulatable())
        _ = simulate.disabled();
    if (simulate.chosen())
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

    var select = (try add_menu.item("&Select")).help("Adds new select to dialog");
    if (select.chosen()) {
        try self.controls.append(self.imtui.allocator, .{ .select = .{
            .schema = .{
                .id = self.nextDesignControlId(),
                .r1 = 3,
                .c1 = 3,
                .r2 = 7,
                .c2 = 7,
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

    if (self.controls.items.len > 2) { // Dialog and one other.
        try controls_menu.separator();

        var reorder = (try controls_menu.item("&Reorder...")).shortcut(.r, .ctrl).help("Changes the order of controls used for tabbing");
        if (reorder.chosen())
            self.reorder_dialog = try ReorderDialog.init(self, focused_dc);
    }

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

fn renderSimulation(self: *Designer) !void {
    self.imtui.text_mode.cursor_inhibit = false;

    const dp = &self.controls.items[0].dialog;

    var dialog = try self.imtui.dialog(
        "designer.SimulationDialog",
        dp.schema.text,
        dp.schema.r2 - dp.schema.r1,
        dp.schema.c2 - dp.schema.c1,
        .centred,
    );

    for (self.controls.items[1..]) |i| {
        switch (i) {
            .dialog => unreachable,
            .button => |p| {
                const b = try dialog.button(p.schema.r1, p.schema.c1, p.schema.text);
                if (p.schema.default)
                    b.default();
                if (p.schema.cancel)
                    b.cancel();
                b.padding(p.schema.padding);
                if (b.chosen())
                    self.confirm_dialog = try ConfirmDialog.init(self, .simulation_end, "Simulation end", "\"{s}\" button pressed.", .{p.schema.text});
            },
            .input => |p| _ = try dialog.input(p.schema.r1, p.schema.c1, p.schema.c2),
            .radio => |p| _ = try dialog.radio(p.schema.r1, p.schema.c1, p.schema.text),
            .checkbox => |p| _ = try dialog.checkbox(p.schema.r1, p.schema.c1, p.schema.text, false),
            .select => |p| {
                var s = try dialog.select(p.schema.r1, p.schema.c1, p.schema.r2, p.schema.c2, 0x70, 1);
                s.items(DesignSelect.ITEMS);
                if (p.schema.horizontal)
                    s.horizontal();
                if (p.schema.select_focus)
                    s.select_focus();
                s.end();
            },
            .label => |p| dialog.label(p.schema.r1, p.schema.c1, p.schema.text),
            .box => |p| dialog.groupbox(p.schema.text, p.schema.r1, p.schema.c1, p.schema.r2, p.schema.c2, 0x70),
            .hrule => |p| dialog.hrule(p.schema.r1, p.schema.c1, p.schema.c2, 0x70),
        }
    }

    try dialog.end();

    if (self.confirm_dialog) |*cd| if (cd.finish(.simulation_end)) {
        self.confirm_dialog = null;
        self.simulating = false;

        self.imtui.unfocus(dialog.impl.control());
        self.imtui.focus_stack.clearRetainingCapacity();
    };
}

fn exportZig(self: *const Designer) !void {
    const out = std.io.getStdOut().writer();

    const dp = &self.controls.items[0].dialog;
    var vc: usize = 0;

    try out.writeAll("----8<----CUT--HERE----8<----\n");
    try out.writeAll("\n");
    try out.writeAll("fn renderDialog(self: *T) !void {\n");
    try std.fmt.format(
        out,
        "    var dialog = try self.imtui.dialog(\"TODO\", \"{}\", {d}, {d}, .centred);\n",
        .{ std.zig.fmtEscapes(dp.schema.text), dp.schema.r2 - dp.schema.r1, dp.schema.c2 - dp.schema.c1 },
    );
    for (self.controls.items[1..]) |i| {
        switch (i) {
            .dialog => unreachable,
            .button => |p| {
                vc += 1;
                try out.writeAll("\n");
                try std.fmt.format(out, "    var button{d} = try dialog.button({d}, {d}, \"{}\");\n", .{ vc, p.schema.r1, p.schema.c1, std.zig.fmtEscapes(p.schema.text) });
                if (p.schema.default)
                    try std.fmt.format(out, "    button{d}.default();\n", .{vc});
                if (p.schema.cancel)
                    try std.fmt.format(out, "    button{d}.cancel();\n", .{vc});
                if (p.schema.padding != 1)
                    try std.fmt.format(out, "    button{d}.padding({d});\n", .{ vc, p.schema.padding });
                try std.fmt.format(out, "    if (button{d}.chosen()) {{\n", .{vc});
                try out.writeAll("        // TODO\n");
                try out.writeAll("    }\n");
            },
            .input => |p| {
                vc += 1;
                try out.writeAll("\n");
                try std.fmt.format(out, "    var input{d} = try dialog.input({d}, {d}, {d});\n", .{ vc, p.schema.r1, p.schema.c1, p.schema.c2 });
            },
            .radio => |p| {
                vc += 1;
                try out.writeAll("\n");
                try std.fmt.format(out, "    var radio{d} = try dialog.radio({d}, {d}, \"{}\");\n", .{ vc, p.schema.r1, p.schema.c1, std.zig.fmtEscapes(p.schema.text) });
            },
            .checkbox => |p| {
                vc += 1;
                try out.writeAll("\n");
                try std.fmt.format(out, "    const checkbox{d}_chosen = false;\n", .{vc});
                try std.fmt.format(out, "    var checkbox{d} = try dialog.checkbox({d}, {d}, \"{}\", checkbox{d}_chosen);\n", .{ vc, p.schema.r1, p.schema.c1, std.zig.fmtEscapes(p.schema.text), vc });
            },
            .select => |p| {
                vc += 1;
                try out.writeAll("\n");
                try std.fmt.format(out, "    const select{d}_selected: usize = 0;\n", .{vc});
                try std.fmt.format(out, "    var select{d} = try dialog.select({d}, {d}, {d}, {d}, 0x70, select{d}_selected);\n", .{ vc, p.schema.r1, p.schema.c1, p.schema.r2, p.schema.c2, vc });
                try std.fmt.format(out, "    select{d}.items(&.{{\"a\", \"b\", \"c\"}});\n", .{vc});
                if (p.schema.horizontal)
                    try std.fmt.format(out, "    select{d}.horizontal();\n", .{vc});
                if (p.schema.select_focus)
                    try std.fmt.format(out, "    select{d}.select_focus();\n", .{vc});
                try std.fmt.format(out, "    select{d}.end();\n", .{vc});
            },
            .label => |p| {
                try out.writeAll("\n");
                try std.fmt.format(out, "    dialog.label({d}, {d}, \"{}\");\n", .{ p.schema.r1, p.schema.c1, std.zig.fmtEscapes(p.schema.text) });
            },
            .box => |p| {
                try out.writeAll("\n");
                try std.fmt.format(out, "    dialog.groupbox(\"{}\", {d}, {d}, {d}, {d}, 0x70);\n", .{ std.zig.fmtEscapes(p.schema.text), p.schema.r1, p.schema.c1, p.schema.r2, p.schema.c2 });
            },
            .hrule => |p| {
                try out.writeAll("\n");
                try std.fmt.format(out, "    dialog.hrule({d}, {d}, {d}, 0x70);\n", .{ p.schema.r1, p.schema.c1, p.schema.c2 });
            },
        }
    }
    try out.writeAll("\n");
    try out.writeAll("    try dialog.end();\n");
    try out.writeAll("}\n");
    try out.writeAll("\n");
    try out.writeAll("----8<----CUT--HERE----8<----\n");
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

fn designSimulatable(self: *const Designer) bool {
    for (self.controls.items) |i|
        switch (i) {
            .dialog, .label, .box, .hrule => {},
            .button, .input, .radio, .checkbox, .select => return true,
        };
    return false;
}

fn dirtyCheck(self: *Designer) !bool {
    const compare = try self.dumpAlloc();
    defer self.imtui.allocator.free(compare);
    return !std.mem.eql(u8, self.snapshot.?, compare);
}

fn startUnsaved(self: *Designer, comptime unsaved_tag: UnsavedDialog.Tag) !bool {
    if (!try self.dirtyCheck())
        return true;
    self.unsaved_dialog = UnsavedDialog.init(self, unsaved_tag);
    return false;
}

const UnsavedResult = enum { nop, action, cancel };

fn checkUnsaved(
    self: *Designer,
    comptime unsaved_tag: UnsavedDialog.Tag,
    comptime confirm_tag: ConfirmDialog.Tag,
) !UnsavedResult {
    const save_tag = @field(SaveDialog.Tag, @tagName(unsaved_tag));

    if (self.unsaved_dialog) |*ud| if (ud.finish(unsaved_tag)) |r| {
        self.unsaved_dialog = null;
        switch (r) {
            .save => {
                try self.startSave(save_tag, confirm_tag);
                return .nop;
            },
            .discard => return .action,
            .cancel => return .cancel,
        }
    };

    return self.checkSave(save_tag, confirm_tag);
}

fn startSave(
    self: *Designer,
    comptime save_tag: SaveDialog.Tag,
    comptime confirm_tag: ConfirmDialog.Tag,
) !void {
    const f = self.save_filename orelse {
        self.save_dialog = try SaveDialog.init(self, save_tag, null);
        return;
    };

    // TODO: fix path/dir thing, see SaveDialog
    const h = try std.fs.cwd().createFile(f, .{});
    defer h.close();

    try self.dump(h.writer());

    try self.confirmSaveAndSnapshot(confirm_tag);
}

fn confirmSaveAndSnapshot(self: *Designer, comptime confirm_tag: ConfirmDialog.Tag) !void {
    self.confirm_dialog = try ConfirmDialog.init(
        self,
        confirm_tag,
        "",
        "Saved to \"{s}\".",
        .{self.save_filename.?},
    );
    if (self.snapshot) |s| self.imtui.allocator.free(s);
    self.snapshot = try self.dumpAlloc();
}

fn checkSave(
    self: *Designer,
    comptime save_tag: SaveDialog.Tag,
    comptime confirm_tag: ConfirmDialog.Tag,
) !UnsavedResult {
    if (self.save_dialog) |*sd| if (sd.finish(save_tag)) |r| {
        self.save_dialog = null;
        switch (r) {
            .saved => try self.confirmSaveAndSnapshot(confirm_tag),
            .canceled => return .cancel,
        }
    };

    if (self.confirm_dialog) |*cd| if (cd.finish(confirm_tag)) {
        self.confirm_dialog = null;
        return .action;
    };

    return .nop;
}
