const std = @import("std");
const Allocator = std.mem.Allocator;

const ErrorInfo = @import("../ErrorInfo.zig");
const isa = @import("./root.zig");

const Assembler = @This();

const Error = error{DuplicateLabel};
pub const RelocError = error{MissingTarget};

allocator: Allocator,
errorinfo: ?*ErrorInfo,
buffer: std.ArrayListUnmanaged(u8) = .{},
labels: std.StringHashMapUnmanaged(usize) = .{},
relocs: std.ArrayListUnmanaged(Reloc) = .{},

const Reloc = struct {
    offset: usize,
    target: []const u8, // Assembler.labels key; it owns the memory.
};

pub fn init(allocator: Allocator, errorinfo: ?*ErrorInfo) Assembler {
    return .{ .allocator = allocator, .errorinfo = errorinfo };
}

pub fn deinit(self: *Assembler) void {
    self.relocs.deinit(self.allocator);
    var it = self.labels.keyIterator();
    while (it.next()) |key_ptr|
        self.allocator.free(key_ptr.*);
    self.labels.deinit(self.allocator);
    self.buffer.deinit(self.allocator);
}

pub fn one(self: *Assembler, e: anytype) (Error || Allocator.Error)!void {
    const writer = self.buffer.writer(self.allocator);

    switch (@TypeOf(e)) {
        isa.Opcode => {
            switch (e.op) {
                .PUSH => {
                    if (e.slot) |slot| {
                        std.debug.assert(e.t == null);
                        const insn = isa.InsnX{ .op = e.op, .rest = 0b1000 };
                        try writer.writeInt(u8, @bitCast(insn), .little);
                        try writer.writeInt(u8, slot, .little);
                    } else {
                        const insn = isa.InsnT{ .op = e.op, .t = e.t.? };
                        try writer.writeInt(u8, @bitCast(insn), .little);
                    }
                },
                .CAST => {
                    const insn = isa.InsnTC{ .op = e.op, .tf = e.tc.?.from, .tt = e.tc.?.to };
                    try writer.writeInt(u8, @bitCast(insn), .little);
                },
                .LET => {
                    const insn = isa.InsnX{ .op = e.op };
                    try writer.writeInt(u8, @bitCast(insn), .little);
                    try writer.writeInt(u8, e.slot.?, .little);
                },
                .PRINT => {
                    const insn = isa.InsnT{ .op = e.op, .t = e.t.? };
                    std.debug.assert(e.slot == null);
                    try writer.writeInt(u8, @bitCast(insn), .little);
                },
                .PRINT_COMMA, .PRINT_LINEFEED, .PRAGMA => {
                    const insn = isa.InsnX{ .op = e.op };
                    try writer.writeInt(u8, @bitCast(insn), .little);
                },
                .ALU => {
                    const insn = isa.InsnAlu{ .op = e.op, .t = e.t.?, .alu = e.alu.? };
                    try writer.writeInt(u16, @bitCast(insn), .little);
                },
                .JUMP => {
                    const insn = isa.InsnC{ .op = e.op, .cond = e.cond.? };
                    try writer.writeInt(u8, @bitCast(insn), .little);
                },
            }
        },
        isa.Value => {
            switch (e) {
                .integer => |i| try writer.writeInt(i16, i, .little),
                .long => |i| try writer.writeInt(i32, i, .little),
                .single => |n| try writer.writeStruct(packed struct { n: f32 }{ .n = n }),
                .double => |n| try writer.writeStruct(packed struct { n: f64 }{ .n = n }),
                .string => |s| {
                    try writer.writeInt(u16, @as(u16, @intCast(s.len)), .little);
                    try writer.writeAll(s);
                },
            }
        },
        isa.Label => {
            const key = try self.allocator.dupe(u8, e.id);
            errdefer self.allocator.free(key);

            const entry = try self.labels.getOrPut(self.allocator, key);
            if (entry.found_existing)
                return ErrorInfo.ret(self, Error.DuplicateLabel, "duplicate jump label: {s}", .{key});

            entry.value_ptr.* = self.buffer.items.len;
        },
        isa.Target => switch (e) {
            .label_id => |l| {
                try self.relocs.append(self.allocator, .{
                    .offset = self.buffer.items.len,
                    .target = l,
                });
                try writer.writeInt(u16, 0xffff, .little);
            },
            .absolute => |n| try writer.writeInt(u16, n, .little),
        },
        else => @compileError("unhandled type: " ++ @typeName(@TypeOf(e))),
    }
}

pub fn link(self: *Assembler) (RelocError || Allocator.Error)!void {
    for (self.relocs.items) |rl| {
        const target = self.labels.get(rl.target) orelse
            return ErrorInfo.ret(self, RelocError.MissingTarget, "missing jump target: {s}", .{rl.target});

        const dest = self.buffer.items[rl.offset..][0..2];
        std.debug.assert(std.mem.readInt(u16, dest, .little) == 0xffff);
        std.mem.writeInt(u16, dest, @intCast(target), .little);
    }
}
