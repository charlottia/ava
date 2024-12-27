const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;
const ini = @import("ini");

const Args = @import("./Args.zig");
const Imtui = imtuilib.Imtui;
const App = imtuilib.App;

const Designer = @import("./Designer.zig");
const DesignDialog = @import("./DesignDialog.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try Args.parse(allocator);
    defer args.deinit();

    const app = try App.init(allocator, .{
        .title = "TextMode Designer",
        .scale = args.scale,
        .sdl_image = true,
    });
    defer app.deinit();

    var imtui = try Imtui.init(allocator, app.renderer, app.font, app.eff_scale);
    defer imtui.deinit();

    var display: enum { both, design_only } = .both;

    var designer: Designer = switch (args.mode) {
        .new => |f| try Designer.initDefaultWithUnderlay(imtui, app.renderer, f),
        .load => |f| try Designer.initFromIni(imtui, app.renderer, f),
    };
    defer designer.deinit();

    var save_dialog_open = false;

    while (imtui.running) {
        while (SDL.pollEvent()) |ev|
            try imtui.processEvent(ev);

        try imtui.newFrame();

        try designer.render();

        var toggle_display_shortcut = try imtui.shortcut(.grave, null);
        if (toggle_display_shortcut.chosen()) {
            display = if (display == .both) .design_only else .both;
        }

        var save_shortcut = try imtui.shortcut(.s, .ctrl);
        if (save_shortcut.chosen()) {
            if (designer.save_filename) |f| {
                const h = try std.fs.cwd().createFile(f, .{});
                defer h.close();

                try designer.dump(h.writer());

                std.log.info("saved to '{s}'", .{f});
            } else {
                save_dialog_open = true;
            }
        }

        if (save_dialog_open) {
            imtui.text_mode.cursor_inhibit = false;

            var sd = try imtui.dialog("Save As", 10, 60);

            sd.groupbox("", 1, 1, 4, 30, 0x70);

            var input = try sd.input(2, 2, 40);
            if (input.initial()) |init|
                try init.appendSlice(allocator, "dialog.ini");

            var ok = try sd.button(4, 4, "OK");
            ok.default();
            if (ok.chosen()) {
                designer.save_filename = try allocator.dupe(u8, input.impl.value.items);
                const h = try std.fs.cwd().createFile(input.impl.value.items, .{});
                defer h.close();

                try designer.dump(h.writer());

                std.log.info("saved to '{s}'", .{input.impl.value.items});

                save_dialog_open = false;
                imtui.unfocus(sd.impl.control());
            }

            var cancel = try sd.button(4, 30, "Cancel");
            cancel.cancel();
            if (cancel.chosen()) {
                save_dialog_open = false;
                imtui.unfocus(sd.impl.control());
            }

            try sd.end();
        }

        try imtui.render();

        if (display == .both and !save_dialog_open)
            try app.renderer.copy(designer.underlay_texture, null, null);

        app.renderer.present();
    }
}
