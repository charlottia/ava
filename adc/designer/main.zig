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
        .new => |f| try Designer.initDefaultWithUnderlay(allocator, app.renderer, f),
        .load => |f| try Designer.initFromIni(allocator, app.renderer, f),
    };
    defer designer.deinit();

    while (imtui.running) {
        while (SDL.pollEvent()) |ev|
            try imtui.processEvent(ev);

        try imtui.newFrame();

        for (designer.controls.items) |*i| {
            switch (i.*) {
                .dialog => |*s| {
                    const dd = try imtui.getOrPutControl(DesignDialog, .{ s.r1, s.c1, s.r2, s.c2, s.title });
                    if (imtui.focus_stack.items.len == 0)
                        try imtui.focus_stack.append(imtui.allocator, dd.impl.control());
                    try dd.sync(allocator, s);
                },
            }
        }

        var toggle_display_shortcut = try imtui.shortcut(.grave, null);
        if (toggle_display_shortcut.chosen()) {
            display = if (display == .both) .design_only else .both;
        }

        try imtui.render();

        if (display == .both)
            try app.renderer.copy(designer.underlay_texture, null, null);

        app.renderer.present();
    }
}
