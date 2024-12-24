const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Args = @import("./Args.zig");
const Imtui = imtuilib.Imtui;
const App = imtuilib.App;

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

    const underlay = if (args.filename) |f| i: {
        const d = try std.fs.cwd().readFileAllocOptions(allocator, f, 10485760, null, @alignOf(u8), 0);
        defer allocator.free(d);
        const t = try SDL.image.loadTextureMem(app.renderer, d, .png);
        try t.setAlphaMod(128);
        try t.setBlendMode(.blend);
        break :i t;
    } else null;

    var imtui = try Imtui.init(allocator, app.renderer, app.font, app.eff_scale);
    defer imtui.deinit();

    var display: enum { both, design_only } = .both;

    while (imtui.running) {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .key_down => |key| if (key.keycode == .grave) {
                    display = if (display == .both) .design_only else .both;
                    continue;
                },
                else => {},
            }
            try imtui.processEvent(ev);
        }

        try imtui.newFrame();

        var dd = try imtui.getOrPutControl(DesignDialog, .{ 5, 5, 20, 60, "Untitled Dialog" });

        if (imtui.focus_stack.items.len == 0)
            try imtui.focus_stack.append(imtui.allocator, dd.impl.control());

        try imtui.render();

        if (display == .both)
            if (underlay) |t|
                try app.renderer.copy(t, null, null);

        app.renderer.present();
    }
}
