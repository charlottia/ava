const Editor = @This();

top: usize,
height: usize,
fullscreened: ?struct {
    old_top: usize,
    old_height: usize,
} = null,

pub fn toggleFullscreen(self: *Editor) void {
    if (self.fullscreened) |pre| {
        self.top = pre.old_top;
        self.height = pre.old_height;
        self.fullscreened = null;
    } else {
        self.fullscreened = .{
            .old_top = self.top,
            .old_height = self.height,
        };
        self.top = 1;
        self.height = 22;
    }
}
