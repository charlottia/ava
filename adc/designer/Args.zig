const std = @import("std");

const Args = @This();

allocator: std.mem.Allocator,

filename: ?[]const u8,
scale: ?f32,

pub fn parse(allocator: std.mem.Allocator) !Args {
    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();

    const argv0 = argv.next().?;

    var filename: ?[]const u8 = null;
    var scale: ?f32 = null;

    var state: enum { root, scale } = .root;
    while (argv.next()) |arg| {
        switch (state) {
            .root => {
                if (std.mem.eql(u8, arg, "--scale"))
                    state = .scale
                else if (filename == null)
                    filename = try allocator.dupe(u8, arg)
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
        .filename = filename,
        .scale = scale,
    };
}

pub fn deinit(self: Args) void {
    if (self.filename) |f| self.allocator.free(f);
}

fn usage(argv0: []const u8) noreturn {
    std.debug.print("usage: {s} [UNDERLAY]\n", .{argv0});
    std.process.exit(1);
}
