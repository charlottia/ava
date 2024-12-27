const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;
const ini = @import("ini");

const DesignDialog = @import("./DesignDialog.zig");

const Designer = @This();

const Control = union(enum) {
    dialog: DesignDialog.Schema,
};

const SaveFile = struct {
    underlay: []const u8 = undefined,
};
const SerDes = ini.SerDes(SaveFile, struct {});

allocator: Allocator,
save_filename: ?[]const u8,
underlay_filename: []const u8,
underlay_texture: SDL.Texture,
controls: std.ArrayListUnmanaged(Control),

pub fn initDefaultWithUnderlay(allocator: Allocator, renderer: SDL.Renderer, underlay: []const u8) !Designer {
    const texture = try loadTextureFromFile(allocator, renderer, underlay);

    var controls = std.ArrayListUnmanaged(Control){};
    try controls.append(allocator, .{ .dialog = .{
        .r1 = 5,
        .c1 = 5,
        .r2 = 20,
        .c2 = 60,
        .title = try allocator.dupe(u8, "Untitled Dialog"),
    } });

    return .{
        .allocator = allocator,
        .save_filename = null,
        .underlay_filename = try allocator.dupe(u8, underlay),
        .underlay_texture = texture,
        .controls = controls,
    };
}

pub fn initFromIni(allocator: Allocator, renderer: SDL.Renderer, inifile: []const u8) !Designer {
    const data = try std.fs.cwd().readFileAllocOptions(allocator, inifile, 10485760, null, @alignOf(u8), 0);
    defer allocator.free(data);

    var p = ini.Parser.init(data, .report);
    const save_file = try SerDes.loadGroup(allocator, &p);

    const texture = try loadTextureFromFile(allocator, renderer, save_file.underlay);
    var controls = std.ArrayListUnmanaged(Control){};

    while (try p.next()) |ev| {
        std.debug.assert(ev == .group);
        var found = false;
        inline for (std.meta.fields(Control)) |f| {
            if (std.mem.eql(u8, ev.group, f.name)) {
                try controls.append(
                    allocator,
                    @unionInit(Control, f.name, try ini.SerDes(f.type, struct {}).loadGroup(allocator, &p)),
                );
                found = true;
                break;
            }
        }
        if (!found)
            std.debug.panic("unknown group '{s}'", .{ev.group});
    }

    return .{
        .allocator = allocator,
        .save_filename = try allocator.dupe(u8, inifile),
        .underlay_filename = save_file.underlay,
        .underlay_texture = texture,
        .controls = controls,
    };
}

pub fn deinit(self: *Designer) void {
    for (self.controls.items) |c|
        switch (c) {
            inline else => |d| d.deinit(self.allocator),
        };
    self.controls.deinit(self.allocator);
    self.underlay_texture.destroy();
    self.allocator.free(self.underlay_filename);
    if (self.save_filename) |f| self.allocator.free(f);
}

pub fn dump(self: *const Designer) !void {
    const out = std.io.getStdOut().writer();

    try SerDes.save(out, .{ .underlay = self.underlay_filename });

    for (self.controls.items) |c| {
        try std.fmt.format(out, "\n[{s}]\n", .{@tagName(c)});
        switch (c) {
            inline else => |d| try ini.SerDes(@TypeOf(d), struct {}).save(out, d),
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
