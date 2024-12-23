const std = @import("std");
const Allocator = std.mem.Allocator;
const known_folders = @import("known-folders");
const ini = @import("ini");

const APP_ID = "net.lottia.ava";

pub fn Preferences(comptime Schema: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        app_dir: std.fs.Dir,
        settings: Schema = .{},

        pub fn init(allocator: Allocator) !Self {
            var lc = (try known_folders.open(allocator, .local_configuration, .{})).?;
            defer lc.close();
            lc.makeDir(APP_ID) catch {};
            const app_dir = try lc.openDir(APP_ID, .{});

            var p = Self{
                .allocator = allocator,
                .app_dir = app_dir,
            };
            try p.load();
            return p;
        }

        pub fn load(self: *Self) !void {
            const d = self.app_dir.readFileAlloc(self.allocator, "adc.ini", 1048576) catch return;
            defer self.allocator.free(d);

            var p = ini.Parser.init(d, .report);
            while (try p.next()) |ev| {
                try self.setFromIni(ev.pair.key, ev.pair.value);
            }
        }

        pub fn save(self: *const Self) !void {
            var out = try self.app_dir.createFile("adc.ini", .{});
            defer out.close();

            inline for (std.meta.fields(Schema)) |f| {
                try std.fmt.format(out.writer(), "{s}=", .{f.name});
                const v = @field(self.settings, f.name);
                switch (f.type) {
                    bool => try out.writeAll(if (v) "true" else "false"),
                    u8 => try std.fmt.format(out.writer(), "0x{x:0>2}", .{v}),
                    else => @compileError("unhandled type: " ++ @typeName(f.type)),
                }
                try out.writeAll("\n");
            }
        }

        pub fn setFromIni(self: *Self, key: []const u8, value: []const u8) !void {
            inline for (std.meta.fields(Schema)) |f|
                if (std.mem.eql(u8, f.name, key)) {
                    switch (f.type) {
                        bool => if (std.ascii.eqlIgnoreCase(value, "true")) {
                            @field(self.settings, f.name) = true;
                        } else if (std.ascii.eqlIgnoreCase(value, "false")) {
                            @field(self.settings, f.name) = false;
                        } else {
                            std.log.warn("unknown boolean value for key '{s}' in adc.ini: '{s}'", .{ key, value });
                        },
                        u8 => if (std.fmt.parseUnsigned(u8, value, 0)) |v| {
                            @field(self.settings, f.name) = v;
                        } else |_| {
                            std.log.warn("unknown integer value for key '{s}' in adc.ini: '{s}'", .{ key, value });
                        },
                        else => @compileError("unhandled type: " ++ @typeName(f.type)),
                    }
                    return;
                };
            std.log.warn("ini key not found in schema: '{s}'", .{key});
        }

        pub fn deinit(self: *Self) void {
            self.app_dir.close();
        }
    };
}
