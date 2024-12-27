const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;
const ini = @import("ini");

const Imtui = imtuilib.Imtui;

const DesignDialog = @import("./DesignDialog.zig");

const Designer = @This();

const Control = union(enum) {
    dialog: DesignDialog.Schema,
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
    for (self.controls.items) |*i| {
        switch (i.*) {
            .dialog => |*s| {
                const dd = try self.imtui.getOrPutControl(DesignDialog, .{ s.r1, s.c1, s.r2, s.c2, s.title });
                if (self.imtui.focus_stack.items.len == 0)
                    try self.imtui.focus_stack.append(self.imtui.allocator, dd.impl.control());
                try dd.sync(self.imtui.allocator, s);
            },
        }
    }
}
