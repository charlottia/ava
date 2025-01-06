const std = @import("std");

const Args = @This();

const Mode = union(enum) {
    empty,
    new: []const u8,
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

    var state: enum { root, scale, new, load } = .root;
    while (argv.next()) |arg| {
        switch (state) {
            .root => {
                if (std.mem.eql(u8, arg, "--scale"))
                    state = .scale
                else if (std.mem.eql(u8, arg, "--new"))
                    state = .new
                else if (std.mem.eql(u8, arg, "--load"))
                    state = .load
                else {
                    std.debug.print("unknown argument: \"{s}\"\n", .{arg});
                    usage(argv0);
                }
            },
            .scale => {
                scale = try std.fmt.parseFloat(f32, arg);
                state = .root;
            },
            .new => {
                std.debug.assert(mode == .empty);
                mode = .{ .new = try allocator.dupe(u8, arg) };
                state = .root;
            },
            .load => {
                std.debug.assert(mode == .empty);
                mode = .{ .load = try allocator.dupe(u8, arg) };
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
        .new => |f| self.allocator.free(f),
        .load => |f| self.allocator.free(f),
    }
}

fn usage(argv0: []const u8) noreturn {
    std.debug.print("usage: {s} [--scale SCALE] [--new UNDERLAY | --load INI]\n", .{argv0});
    std.process.exit(1);
}
