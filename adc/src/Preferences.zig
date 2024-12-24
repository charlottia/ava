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

        const SerDes = ini.SerDes(Schema, struct {
            pub const DeserializeError = error{ParseError};
            pub fn deserialize(comptime T: type, _: Allocator, key: []const u8, value: []const u8) DeserializeError!T {
                switch (T) {
                    bool => if (std.ascii.eqlIgnoreCase(value, "true")) {
                        return true;
                    } else if (std.ascii.eqlIgnoreCase(value, "false")) {
                        return false;
                    } else {
                        std.log.warn("unknown boolean value for key '{s}' in adc.ini: '{s}'", .{ key, value });
                        return error.ParseError;
                    },
                    u8 => if (std.fmt.parseUnsigned(u8, value, 0)) |v| {
                        return v;
                    } else |_| {
                        std.log.warn("unknown integer value for key '{s}' in adc.ini: '{s}'", .{ key, value });
                        return error.ParseError;
                    },
                    else => @compileError("unhandled type: " ++ @typeName(T)),
                }
            }

            pub fn serialize(comptime T: type, writer: anytype, key: []const u8, value: T) @TypeOf(writer).Error!void {
                _ = key;
                switch (T) {
                    bool => try writer.writeAll(if (value) "true" else "false"),
                    u8 => try std.fmt.format(writer, "0x{x:0>2}", .{value}),
                    else => @compileError("unhandled type: " ++ @typeName(T)),
                }
            }
        });

        pub fn load(self: *Self) !void {
            const d = self.app_dir.readFileAlloc(self.allocator, "adc.ini", 1048576) catch return;
            defer self.allocator.free(d);

            self.settings = try SerDes.load(self.allocator, d);
        }

        pub fn save(self: *const Self) !void {
            var out = try self.app_dir.createFile("adc.ini", .{});
            defer out.close();

            try SerDes.save(out.writer(), self.settings);
        }

        pub fn deinit(self: *Self) void {
            self.app_dir.close();
        }
    };
}
