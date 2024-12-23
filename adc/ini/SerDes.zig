const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Parser = @import("./Parser.zig");

pub fn SerDes(comptime Schema: type, comptime Config: type) type {
    return struct {
        fn load(input: []const u8) (Parser.Error || Config.DeserializeError)!Schema {
            var s = Schema{};
            const c = Config.Context{};
            var p = Parser.init(input, .report);
            while (try p.next()) |ev| {
                inline for (std.meta.fields(Schema)) |f|
                    if (std.mem.eql(u8, ev.pair.key, f.name)) {
                        @field(s, f.name) = try Config.deserialize(
                            f.type,
                            c,
                            ev.pair.key,
                            ev.pair.value,
                        );
                    };
            }
            return s;
        }

        fn saveAlloc(allocator: Allocator, v: Schema) ![]u8 {
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(allocator);

            const c = Config.Context{};
            const writer = buf.writer(allocator);

            inline for (std.meta.fields(Schema)) |f| {
                try std.fmt.format(writer, "{s}=", .{f.name});
                const value = @field(v, f.name);
                try Config.serialize(f.type, c, writer, f.name, value);
                try writer.writeByte('\n');
            }

            return buf.toOwnedSlice(allocator);
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
    });

    const v = try SchemaSD.load(
        \\integer=0x42
        \\string=Henlo
        \\boolean= 1
    );
    defer testing.allocator.free(v.string);
    try testing.expectEqualDeep(Schema{
        .string = "HENLO",
        .integer = 66,
        .boolean = true,
    }, v);

    const out = try SchemaSD.saveAlloc(testing.allocator, v);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(
        \\string=henlo
        \\integer=0o102
        \\boolean=1
        \\
    , out);
}
