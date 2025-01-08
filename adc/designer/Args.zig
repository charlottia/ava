const std = @import("std");

const Args = @This();

const Mode = union(enum) {
    empty,
    load: []const u8,
};

allocator: std.mem.Allocator,

mode: Mode,
scale: ?f32,

pub fn parse(allocator: std.mem.Allocator) !Args {
    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();

    const argv0 = argv.next().?;

    var mode: Mode = .empty;
    var scale: ?f32 = null;

    var state: enum { root, scale } = .root;
    while (argv.next()) |arg| {
        switch (state) {
            .root => {
                if (std.mem.eql(u8, arg, "--scale"))
                    state = .scale
                else if (mode == .empty)
                    mode = .{ .load = try allocator.dupe(u8, arg) }
                else {
                    std.debug.print("unknown argument: \"{s}\"\n", .{arg});
                    usage(argv0);
                }
            },
            .scale => {
                scale = try std.fmt.parseFloat(f32, arg);
                state = .root;
            },
        }
    }

    if (state != .root)
        usage(argv0);

    return .{
        .allocator = allocator,
        .mode = mode,
        .scale = scale,
    };
}

pub fn deinit(self: Args) void {
    switch (self.mode) {
        .empty => {},
        .load => |f| self.allocator.free(f),
    }
}

fn usage(argv0: []const u8) noreturn {
    std.debug.print("usage: {s} [--scale SCALE] [DIALOG.INI]\n", .{argv0});
    std.process.exit(1);
}
