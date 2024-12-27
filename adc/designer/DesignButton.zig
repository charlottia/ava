const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const ini = @import("ini");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignDialog = @import("./DesignDialog.zig");

const DesignButton = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    parent: *DesignDialog.Impl,

    // state
    r1: usize,
    c1: usize,
    r2: usize = undefined,
    c2: usize = undefined,
    label: std.ArrayListUnmanaged(u8),
    label_orig: std.ArrayListUnmanaged(u8) = .{},

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .no_key = true,
                .parent = parent,
                .deinit = deinit,
                .isMouseOver = isMouseOver,
                // .handleMouseDown = handleMouseDown,
                // .handleMouseDrag = handleMouseDrag,
                // .handleMouseUp = handleMouseUp,
            },
        };
    }

    pub fn describe(self: *Impl, _: *DesignDialog.Impl, _: usize, _: usize, _: usize, _: []const u8) void {
        self.r2 = self.r1;
        self.c2 = self.c1 + 4 + self.label.items.len;

        const r1 = self.parent.r1 + self.r1;
        const c1 = self.parent.c1 + self.c1;
        const c2 = self.parent.c1 + self.c2;
        self.imtui.text_mode.write(r1, c1, "<"); // should be 0x7f if 'default'
        self.imtui.text_mode.writeAccelerated(r1, c1 + 2, self.label.items, true);
        self.imtui.text_mode.write(r1, c2 - 1, ">"); // should be 0x7f if 'default'
    }

    fn parent(ptr: *const anyopaque) ?Imtui.Control {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.parent.control();
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.label.deinit(self.imtui.allocator);
        self.label_orig.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return (self.imtui.mouse_row >= self.parent.r1 + self.r1 and self.imtui.mouse_row < self.parent.r1 + self.r2 and
            self.imtui.mouse_col >= self.parent.c1 + self.c1 and self.imtui.mouse_col < self.parent.c1 + self.c2);
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: *DesignDialog.Impl, ix: usize, _: usize, _: usize, _: []const u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}", .{ "designer.DesignButton", ix });
}

pub fn create(imtui: *Imtui, parent: *DesignDialog.Impl, ix: usize, r1: usize, c1: usize, label: []const u8) !DesignButton {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .parent = parent,
        .r1 = r1,
        .c1 = c1,
        .label = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, label)),
    };
    d.describe(parent, ix, r1, c1, label);
    return .{ .impl = d };
}

pub const Schema = struct {
    r1: usize,
    c1: usize,
    label: []const u8,

    pub fn deinit(self: Schema, allocator: Allocator) void {
        allocator.free(self.label);
    }
};

pub fn sync(self: DesignButton, allocator: Allocator, schema: *Schema) !void {
    schema.r1 = self.impl.r1;
    schema.c1 = self.impl.c1;
    if (!std.mem.eql(u8, schema.label, self.impl.label.items)) {
        allocator.free(schema.label);
        schema.label = try allocator.dupe(u8, self.impl.label.items);
    }
}
