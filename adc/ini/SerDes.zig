const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Parser = @import("./Parser.zig");

pub fn SerDes(comptime Schema: type, comptime Config: type) type {
    comptime var ArrayKeys: []const [:0]const u8 = &.{};
    comptime var ArrayStateEnumFields: []const std.builtin.Type.EnumField = &.{};
    comptime var ArrayElemStateFields: []const std.builtin.Type.UnionField = &.{};
    comptime var ArrayStateFields: []const std.builtin.Type.StructField = &.{};
    for (std.meta.fields(Schema)) |f| {
        switch (@typeInfo(f.type)) {
            .Pointer => |p| if (p.size == .Slice and p.child != u8) {
                ArrayKeys = ArrayKeys ++ [_][:0]const u8{f.name};
                ArrayStateEnumFields = ArrayStateEnumFields ++ [_]std.builtin.Type.EnumField{.{
                    .name = f.name,
                    .value = ArrayStateEnumFields.len,
                }};
                ArrayElemStateFields = ArrayElemStateFields ++ [_]std.builtin.Type.UnionField{.{
                    .name = f.name,
                    .type = *p.child,
                    .alignment = @alignOf(p.child),
                }};
                ArrayStateFields = ArrayStateFields ++ [_]std.builtin.Type.StructField{.{
                    .name = f.name,
                    .type = std.ArrayListUnmanaged(p.child),
                    .default_value = &std.ArrayListUnmanaged(p.child){},
                    .is_comptime = false,
                    .alignment = @alignOf(std.ArrayListUnmanaged(p.child)),
                }};
            },
            else => {},
        }
    }

    const Underlying = u8;
    std.debug.assert(ArrayKeys.len <= std.math.maxInt(Underlying) + 1);

    const ArrayStateEnum = @Type(.{ .Enum = .{
        .tag_type = Underlying,
        .fields = ArrayStateEnumFields,
        .decls = &.{},
        .is_exhaustive = true,
    } });

    const ArrayElemState = @Type(.{ .Union = .{
        .layout = .auto,
        .tag_type = ArrayStateEnum,
        .fields = ArrayElemStateFields,
        .decls = &.{},
    } });

    const ArrayState = @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = ArrayStateFields,
        .decls = &.{},
        .is_tuple = false,
    } });

    return struct {
        pub fn load(allocator: Allocator, input: []const u8) (Parser.Error || Config.DeserializeError)!Schema {
            var s: Schema = undefined;
            var p = Parser.init(input, .report);
            var array_elem_state: ?ArrayElemState = null;
            var array_state: ArrayState = .{};

            while (try p.next()) |ev|
                switch (ev) {
                    .group => |group| {
                        var found = false;
                        inline for (ArrayKeys) |k|
                            if (std.mem.eql(u8, group, k)) {
                                const ptr = try @field(array_state, k).addOne(allocator);
                                array_elem_state = @unionInit(ArrayElemState, k, ptr);
                                found = true;
                                break;
                            };
                        if (!found)
                            std.debug.print("unknown group '{s}' referenced\n", .{group});
                    },
                    .pair => |pair| {
                        var found = false;
                        if (array_elem_state) |*aes| {
                            out: inline for (std.meta.fields(ArrayStateEnum)) |f|
                                if (aes.* == @as(ArrayStateEnum, @enumFromInt(f.value)))
                                    inline for (std.meta.fields(std.meta.Child(std.meta.TagPayloadByName(ArrayElemState, f.name)))) |sf|
                                        if (std.mem.eql(u8, pair.key, sf.name)) {
                                            @field(@field(aes.*, f.name), sf.name) = try Config.deserialize(sf.type, allocator, pair.key, pair.value);
                                            found = true;
                                            break :out;
                                        };
                        } else inline for (std.meta.fields(Schema)) |f|
                            if (std.mem.eql(u8, pair.key, f.name)) {
                                @field(s, f.name) = try Config.deserialize(f.type, allocator, pair.key, pair.value);
                                found = true;
                                break;
                            };
                        if (!found)
                            std.debug.print("unknown field '{s}' referenced{s}\n", .{ pair.key, if (array_elem_state != null) " in array" else "" });
                    },
                };

            inline for (std.meta.fields(ArrayState)) |f|
                @field(s, f.name) = try @field(array_state, f.name).toOwnedSlice(allocator);

            return s;
        }

        pub fn save(writer: anytype, v: Schema) @TypeOf(writer).Error!void {
            inline for (std.meta.fields(Schema)) |f| {
                try std.fmt.format(writer, "{s}=", .{f.name});
                const value = @field(v, f.name);
                try Config.serialize(f.type, writer, f.name, value);
                try writer.writeByte('\n');
            }
        }
    };
}

test "base" {
    const Schema = struct {
        string: []const u8,
        integer: u32,
        boolean: bool,
    };

    const SchemaSD = SerDes(Schema, struct {
        const DeserializeError = Allocator.Error || std.fmt.ParseIntError;

        fn deserialize(comptime T: type, allocator: Allocator, key: []const u8, value: []const u8) DeserializeError!T {
            _ = key;
            return switch (T) {
                []const u8 => try std.ascii.allocUpperString(allocator, value),
                u32 => try std.fmt.parseUnsigned(u32, value, 0),
                bool => std.mem.eql(u8, value, "1"),
                else => unreachable,
            };
        }

        fn serialize(comptime T: type, writer: anytype, key: []const u8, value: T) @TypeOf(writer).Error!void {
            _ = key;
            switch (T) {
                []const u8 => {
                    const lowered = try std.ascii.allocLowerString(testing.allocator, value);
                    defer testing.allocator.free(lowered);
                    try writer.writeAll(lowered);
                },
                u32 => try std.fmt.format(writer, "0o{o}", .{value}),
                bool => try writer.writeAll(if (value) "1" else "0"),
                else => unreachable,
            }
        }
    });

    const v = try SchemaSD.load(testing.allocator,
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

test "array" {
    const Schema = struct {
        thingy: []const u8,
        stuff: []const struct {
            a: usize,
            b: usize,
        },
        garage: []const struct {
            n: usize,
        },
    };

    const SchemaSD = SerDes(Schema, struct {
        const DeserializeError = Allocator.Error || std.fmt.ParseIntError;

        fn deserialize(comptime T: type, allocator: Allocator, key: []const u8, value: []const u8) DeserializeError!T {
            _ = key;
            _ = allocator;
            return switch (T) {
                []const u8 => value,
                usize => try std.fmt.parseUnsigned(usize, value, 0),
                else => unreachable,
            };
        }

        fn serialize(comptime T: type, writer: anytype, key: []const u8, value: T) @TypeOf(writer).Error!void {
            _ = key;
            switch (T) {
                []const u8 => {
                    const lowered = try std.ascii.allocLowerString(testing.allocator, value);
                    defer testing.allocator.free(lowered);
                    try writer.writeAll(lowered);
                },
                u32 => try std.fmt.format(writer, "0o{o}", .{value}),
                bool => try writer.writeAll(if (value) "1" else "0"),
                else => unreachable,
            }
        }
    });

    const v = try SchemaSD.load(testing.allocator,
        \\thingy=yo!
        \\[stuff]
        \\a=1
        \\b=2
        \\
        \\[stuff]
        \\a=3
        \\b=4
        \\
        \\   [garage]  
        \\   n = 42
    );
    defer {
        testing.allocator.free(v.stuff);
        testing.allocator.free(v.garage);
    }
    try testing.expectEqualDeep(Schema{
        .thingy = "yo!",
        .stuff = &.{
            .{ .a = 1, .b = 2 },
            .{ .a = 3, .b = 4 },
        },
        .garage = &.{
            .{ .n = 42 },
        },
    }, v);
}
