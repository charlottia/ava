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

        // TODO: work out a way to transparent only certain things (so we can
        //       see through the dialog we've made)
        //  - "in front" gives a poor man's version of this
        // TODO: make DesignButton belong to DesignDialog etc. See if we should
        //       be reusing real Dialog architecture.

        try app.renderer.setColorRGBA(0, 0, 0, 0);
        try app.renderer.clear();

        if (designer.display == .behind and !designer.inhibit_underlay)
            try app.renderer.copy(designer.underlay_texture, null, null);

        try imtui.render();

        if (designer.display == .in_front and !designer.inhibit_underlay) {
            const r = SDL.Rectangle{
                .x = 0,
                .y = 16,
                .width = 720,
                .height = 16 * 23,
            };
            try app.renderer.copy(designer.underlay_texture, r, r);
        }

        app.renderer.present();
    }
}
