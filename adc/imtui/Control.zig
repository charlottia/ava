const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("./Imtui.zig");

const Control = @This();

pub const Base = struct {
    imtui: *Imtui,
    generation: usize,
};

pub const VTable = struct {
    orphan: bool = false,
    no_key: bool = false,
    no_mouse: bool = false,

    parent: ?*const fn (self: *const anyopaque) ?Control = null,
    deinit: *const fn (self: *anyopaque) void,
    accelGet: ?*const fn (self: *const anyopaque) ?u8 = null,
    accelerate: ?*const fn (self: *anyopaque) Allocator.Error!void = null,
    handleKeyPress: ?*const fn (self: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) Allocator.Error!void = null,
    handleKeyUp: ?*const fn (self: *anyopaque, keycode: SDL.Keycode) Allocator.Error!void = null,
    isMouseOver: ?*const fn (self: *const anyopaque) bool = null,
    handleMouseDown: ?*const fn (self: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) Allocator.Error!?Control = null,
    handleMouseDrag: ?*const fn (self: *anyopaque, b: SDL.MouseButton) Allocator.Error!void = null,
    handleMouseUp: ?*const fn (self: *anyopaque, b: SDL.MouseButton, clicks: u8) Allocator.Error!void = null,
    onFocus: ?*const fn (self: *anyopaque) Allocator.Error!void = null,
    onBlur: ?*const fn (self: *anyopaque) Allocator.Error!void = null,
};

ptr: *anyopaque,
vtable: *const VTable,

pub fn assertBase(comptime T: type) void {
    const base_fields = std.meta.fields(Base);
    const timpl_fields = std.meta.fields(T.Impl);

    inline for (0..base_fields.len) |i| {
        if (!comptime std.mem.eql(u8, base_fields[i].name, timpl_fields[i].name))
            @compileError(std.fmt.comptimePrint(
                "field {d} of {s}.Impl name does not match Base's: {s} != {s}",
                .{ i, @typeName(T), timpl_fields[i].name, base_fields[i].name },
            ));
        if (!comptime std.meta.eql(base_fields[i].type, timpl_fields[i].type))
            @compileError(std.fmt.comptimePrint(
                "field {d} of {s}.Impl type does not match Base's: {s} != {s}",
                .{ i, @typeName(T), @typeName(timpl_fields[i].type), @typeName(base_fields[i].type) },
            ));
    }
}

pub fn is(self: Control, comptime T: type) ?*T {
    // HACK
    if (self.vtable.deinit != &T.deinit)
        return null;
    return @ptrCast(@alignCast(self.ptr));
}

pub fn as(self: Control, comptime T: type) *T {
    return self.is(T).?;
}

pub fn same(self: Control, other: Control) bool {
    return self.vtable == other.vtable and self.ptr == other.ptr;
}

pub fn lives(self: Control, n: usize) bool {
    if (self.generationGet() < n - 1)
        return false;
    self.generationSet(n);
    return true;
}

pub fn generationGet(self: Control) usize {
    const base: *const Base = @ptrCast(@alignCast(self.ptr));
    return base.generation;
}

fn generationSet(self: Control, n: usize) void {
    const base: *Base = @ptrCast(@alignCast(self.ptr));
    base.generation = n;
}

// Pure forwarded methods follow.

pub fn parent(self: Control) ?Control {
    return if (self.vtable.orphan) null else self.vtable.parent.?(self.ptr);
}

pub fn deinit(self: Control) void {
    self.vtable.deinit(self.ptr);
}

pub fn accelGet(self: Control) ?u8 {
    return self.vtable.accelGet.?(self.ptr);
}

pub fn accelerate(self: Control) !void {
    return self.vtable.accelerate.?(self.ptr);
}

pub fn handleKeyPress(self: Control, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    return if (self.vtable.no_key) {} else self.vtable.handleKeyPress.?(self.ptr, keycode, modifiers);
}

pub fn handleKeyUp(self: Control, keycode: SDL.Keycode) !void {
    return if (self.vtable.no_key) {} else self.vtable.handleKeyUp.?(self.ptr, keycode);
}

pub fn isMouseOver(self: Control) bool {
    return if (self.vtable.no_mouse) false else self.vtable.isMouseOver.?(self.ptr);
}

pub fn handleMouseDown(self: Control, b: SDL.MouseButton, clicks: u8, cm: bool) !?Control {
    return if (self.vtable.no_mouse) null else self.vtable.handleMouseDown.?(self.ptr, b, clicks, cm);
}

pub fn handleMouseDrag(self: Control, b: SDL.MouseButton) !void {
    return if (self.vtable.no_mouse) {} else self.vtable.handleMouseDrag.?(self.ptr, b);
}

pub fn handleMouseUp(self: Control, b: SDL.MouseButton, clicks: u8) !void {
    return if (self.vtable.no_mouse) {} else self.vtable.handleMouseUp.?(self.ptr, b, clicks);
}

pub fn onFocus(self: Control) !void {
    return if (self.vtable.onFocus) |cb| cb(self.ptr) else {};
}

pub fn onBlur(self: Control) !void {
    return if (self.vtable.onBlur) |cb| cb(self.ptr) else {};
}
