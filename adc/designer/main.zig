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

    while (imtui.running) {
        while (SDL.pollEvent()) |ev|
            try imtui.processEvent(ev);

        try imtui.newFrame();

        try designer.render();

        var toggle_display_shortcut = try imtui.shortcut(.grave, null);
        if (toggle_display_shortcut.chosen()) {
            display = if (display == .both) .design_only else .both;
        }

        try imtui.render();

        if (display == .both and !designer.inhibit_underlay)
            try app.renderer.copy(designer.underlay_texture, null, null);

        app.renderer.present();
    }
}
