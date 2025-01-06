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

    var prefs = try Designer.Prefs.init(allocator);
    try prefs.save();
    defer prefs.deinit();

    const app = try App.init(allocator, .{
        .title = "TextMode Designer",
        .scale = args.scale,
        .sdl_image = true,
    });
    defer app.deinit();

    var imtui = try Imtui.init(allocator, app.renderer, app.font, app.eff_scale);
    defer imtui.deinit();

    var designer: Designer = switch (args.mode) {
        .empty => try Designer.initDefaultWithUnderlay(imtui, prefs, app.renderer, null),
        .new => |f| try Designer.initDefaultWithUnderlay(imtui, prefs, app.renderer, f),
        .load => |f| try Designer.initFromIni(imtui, prefs, app.renderer, f),
    };
    defer designer.deinit();

    _ = try SDL.showCursor(prefs.settings.system_cursor);

    while (imtui.running) {
        while (SDL.pollEvent()) |ev|
            try imtui.processEvent(ev);

        try imtui.newFrame();

        try designer.render();

        try app.renderer.setColorRGBA(0, 0, 0, 0);
        try app.renderer.clear();

        if (designer.display == .behind and !designer.inhibit_underlay) {
            const r = SDL.Rectangle{
                .x = 0,
                .y = 0,
                .width = 720,
                .height = 16 * 25,
            };
            if (designer.underlay_texture) |t|
                try app.renderer.copy(t, r, r);
        }

        try imtui.render();

        if (designer.display == .in_front and !designer.inhibit_underlay) {
            const r = SDL.Rectangle{
                .x = 0,
                .y = 16,
                .width = 720,
                .height = 16 * 23,
            };
            if (designer.underlay_texture) |t|
                try app.renderer.copy(t, r, r);
        }

        app.renderer.present();

        if (designer.event) |ev| switch (ev) {
            .new => {
                designer.deinit();
                designer = try Designer.initDefaultWithUnderlay(imtui, prefs, app.renderer, null);
                // Ensure we have a control hierarchy before possibly looping
                // and passing any events to Imtui.
                try imtui.newFrame();
                try designer.render();
            },
        };
    }
}
