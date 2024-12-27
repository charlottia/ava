const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const ini = @import("ini");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignButton = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    // state
    r: usize,
    c: usize,
    label: std.ArrayListUnmanaged(u8),
    label_orig: std.ArrayListUnmanaged(u8),

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .orphan = true,
                .no_key = true,
                .no_mouse = true,
                .deinit = deinit,
            },
        };
    }

    pub fn describe(self: *Impl, _: usize, _: usize, _: usize, _: []const u8) void {
        self.imtui.text_mode.writeAccelerated(self.r, self.c, self.label.items, true);
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.label.deinit(self.imtui.allocator);
        self.label_orig.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.state == .title_edit or (self.imtui.mouse_row >= self.r1 and self.imtui.mouse_row < self.r2 and
            self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2);
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, ix: usize, _: usize, _: usize, _: []const u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}", .{ "designer.DesignButton", ix });
}

pub fn create(imtui: *Imtui, ix: usize, r: usize, c: usize, label: []const u8) !DesignButton {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .r = r,
        .c = c,
        .label = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, label)),
        .label_orig = .{},
    };
    d.describe(ix, r, c, label);
    return .{ .impl = d };
}

pub const Schema = struct {
    r: usize,
    c: usize,
    label: []const u8,

    pub fn deinit(self: Schema, allocator: Allocator) void {
        allocator.free(self.label);
    }
};

pub fn sync(self: DesignButton, allocator: Allocator, schema: *Schema) !void {
    schema.r = self.impl.r;
    schema.c = self.impl.c;
    if (!std.mem.eql(u8, schema.label, self.impl.label.items)) {
        allocator.free(schema.label);
        schema.label = try allocator.dupe(u8, self.impl.label.items);
    }
}
