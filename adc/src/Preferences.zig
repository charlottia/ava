const std = @import("std");
const Allocator = std.mem.Allocator;
const known_folders = @import("known-folders");

const APP_ID = "net.lottia.ava";

const Preferences = @This();

allocator: Allocator,
app_dir: std.fs.Dir,
settings: std.StringHashMap(Value),

const Value = union(enum) {
    boolean: bool,
};

pub fn init(allocator: Allocator, defaults: anytype) !Preferences {
    var lc = (try known_folders.open(allocator, .local_configuration, .{})).?;
    defer lc.close();
    lc.makeDir(APP_ID) catch {};
    const app_dir = try lc.openDir(APP_ID, .{});

    var p = Preferences{
        .allocator = allocator,
        .app_dir = app_dir,
        .settings = std.StringHashMap(Value).init(allocator),
    };

    inline for (@typeInfo(@TypeOf(defaults)).Struct.fields) |e| {
        const v: Value = switch (e.type) {
            bool => .{ .boolean = @field(defaults, e.name) },
            else => unreachable,
        };
        try p.settings.putNoClobber(e.name, v);
    }

    try p.load();

    return p;
}

pub fn load(self: *Preferences) !void {
    const ini = self.app_dir.readFileAlloc(self.allocator, "adc.ini", 1048576) catch return;
    defer self.allocator.free(ini);

    var state: enum {
        idle,
        comment,
        key,
        value,
    } = .idle;
    var key_start: usize = undefined;
    var value_start: usize = undefined;
    var i: usize = 0;
    while (i < ini.len) : (i += 1) {
        const c = ini[i];
        switch (state) {
            .idle => switch (c) {
                ';', '#' => state = .comment,
                'a'...'z' => {
                    key_start = i;
                    state = .key;
                },
                ' ', '\t', '\r', '\n' => {},
                else => std.log.warn("unknown character in adc.ini: '{c}'", .{c}),
            },
            .comment => switch (c) {
                '\r', '\n' => state = .idle,
                else => {},
            },
            .key => switch (c) {
                'a'...'z', '_', ' ' => {},
                '=' => {
                    value_start = i + 1;
                    state = .value;
                },
                '\r', '\n' => {
                    std.log.warn("key without value in adc.ini: '{s}'", .{ini[key_start..i]});
                    state = .idle;
                },
                else => std.log.warn("unknown character in adc.ini: '{c}'", .{c}),
            },
            .value => switch (c) {
                '\r', '\n' => {
                    const key = std.mem.trim(u8, ini[key_start .. value_start - 1], "\t ");
                    const value = std.mem.trim(u8, ini[value_start..i], "\t ");
                    try self.setFromIni(key, value);
                    state = .idle;
                },
                else => {},
            },
        }
    }

    switch (state) {
        .idle, .comment => {},
        .key => std.log.warn("key without value at end of adc.ini: '{s}'", .{ini[key_start..]}),
        .value => {
            const key = std.mem.trim(u8, ini[key_start .. value_start - 1], "\t ");
            const value = std.mem.trim(u8, ini[value_start..], "\t ");
            try self.setFromIni(key, value);
        },
    }
}

pub fn save(self: *const Preferences) !void {
    var f = try self.app_dir.createFile("adc.ini", .{});
    defer f.close();

    var it = self.settings.iterator();
    while (it.next()) |e| {
        try std.fmt.format(f.writer(), "{s}=", .{e.key_ptr.*});
        switch (e.value_ptr.*) {
            .boolean => |b| try f.writeAll(if (b) "true" else "false"),
        }
        try f.writeAll("\n");
    }
}

pub fn set(self: *Preferences, values: anytype) void {
    inline for (@typeInfo(@TypeOf(values)).Struct.fields) |e| {
        const v: Value = switch (e.type) {
            bool => .{ .boolean = @field(values, e.name) },
            else => unreachable,
        };
        const ptr = self.settings.getPtr(e.name).?;
        ptr.* = v;
    }
}

pub fn setFromIni(self: *Preferences, key: []const u8, value: []const u8) !void {
    const ptr = self.settings.getPtr(key).?;
    switch (ptr.*) {
        .boolean => |*v| {
            if (std.ascii.eqlIgnoreCase(value, "true"))
                v.* = true
            else if (std.ascii.eqlIgnoreCase(value, "false"))
                v.* = false
            else
                std.log.warn("unknown boolean value for key '{s}' in adc.ini: '{s}'", .{ key, value });
            std.log.info("set {s} to {any} ('{s}')", .{ key, v.*, value });
        },
    }
}

pub fn get(self: *const Preferences, comptime T: type, key: anytype) T {
    const v = self.settings.get(@tagName(key)).?;
    return switch (T) {
        bool => v.boolean,
        else => unreachable,
    };
}

pub fn deinit(self: *Preferences) void {
    // for (self.settings.valueIterator()) |vit| {}
    self.settings.deinit();
    self.app_dir.close();
}
