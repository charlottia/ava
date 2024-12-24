const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Parser = @import("./Parser.zig");

pub fn SerDes(comptime Schema: type, comptime Config: type) type {
    return struct {
        pub fn loadInto(input: []const u8, dest: *Schema) (Parser.Error || Config.DeserializeError)!void {
            var p = Parser.init(input, .report);
            while (try p.next()) |ev| {
                inline for (std.meta.fields(Schema)) |f|
                    if (std.mem.eql(u8, ev.pair.key, f.name)) {
                        if (@hasDecl(Config, "Context"))
                            @field(dest, f.name) = try Config.deserialize(f.type, Config.Context{}, ev.pair.key, ev.pair.value)
                        else
                            @field(dest, f.name) = try Config.deserialize(f.type, ev.pair.key, ev.pair.value);
                    };
            }
        }

        pub fn save(writer: anytype, v: Schema) @TypeOf(writer).Error!void {
            inline for (std.meta.fields(Schema)) |f| {
                try std.fmt.format(writer, "{s}=", .{f.name});
                const value = @field(v, f.name);
                if (@hasDecl(Config, "Context"))
                    try Config.serialize(f.type, Config.Context{}, writer, f.name, value)
                else
                    try Config.serialize(f.type, writer, f.name, value);
                try writer.writeByte('\n');
            }
        }
    };
}

test SerDes {
    const Schema = struct {
        string: []const u8 = undefined,
        integer: u32 = undefined,
        boolean: bool = undefined,
    };

    const SchemaSD = SerDes(Schema, struct {
        const Context = struct { allocator: Allocator = testing.allocator };

        const DeserializeError = Allocator.Error || std.fmt.ParseIntError;

        fn deserialize(comptime T: type, context: Context, key: []const u8, value: []const u8) DeserializeError!T {
            _ = key;
            return switch (T) {
                []const u8 => try std.ascii.allocUpperString(context.allocator, value),
                u32 => try std.fmt.parseUnsigned(u32, value, 0),
                bool => std.mem.eql(u8, value, "1"),
                else => unreachable,
            };
        }

        fn serialize(comptime T: type, context: Context, writer: anytype, key: []const u8, value: T) @TypeOf(writer).Error!void {
            _ = key;
            switch (T) {
                []const u8 => {
                    const lowered = try std.ascii.allocLowerString(context.allocator, value);
                    defer context.allocator.free(lowered);
                    try writer.writeAll(lowered);
                },
                u32 => try std.fmt.format(writer, "0o{o}", .{value}),
                bool => try writer.writeAll(if (value) "1" else "0"),
                else => unreachable,
            }
        }
    });

    var v = Schema{};
    try SchemaSD.loadInto(
        \\integer=0x42
        \\string=Henlo
        \\boolean= 1
    , &v);
    defer testing.allocator.free(v.string);
    try testing.expectEqualDeep(Schema{
        .string = "HENLO",
        .integer = 66,
        .boolean = true,
    }, v);

    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(testing.allocator);
    try SchemaSD.save(out.writer(testing.allocator), v);
    try testing.expectEqualStrings(
        \\string=henlo
        \\integer=0o102
        \\boolean=1
        \\
    , out.items);
}
