const std = @import("std");
const Allocator = std.mem.Allocator;

/// The chosen allocator for this project.
const allocator = std.heap.page_allocator;

/// The 'omino' struct.
const Omino = struct {
    size: u8,
    array: []bool,

    pub fn init(size: u8) !Omino {
        return Omino {
            .size = size,
            .array = try allocator.alloc(bool, size*size),
        };
    }

    pub fn deinit(self: Omino) void {
        allocator.free(self.array);
    }

    pub fn toStr(self: Omino) ![]const u8 {
        var buf: []u8 = try allocator.alloc(u8, 128);
        var i: u8 = 0;
        var j: u8 = 0;
        var index: u8 = 0;
        var pos: u8 = 0;

        while (i < self.size) {
            j = 0;
            while (j < self.size) {
                buf[pos] = if (self.array[index]) '#' else '.';
                pos += 1;
                index += 1;
                j += 1;
            }
            buf[pos] = '\n';
            pos += 1;
            i += 1;
        }
        buf[pos] = 0;
        pos += 1;
        
        return buf;
    }
};

/// Main.
pub fn main() !void {
    std.debug.warn("Running...\n", .{});
    
    var omino = try Omino.init(4);
    defer omino.deinit();
    omino.array[1] = true;
    omino.array[4] = true;
    omino.array[5] = true;
    omino.array[15] = true;
    var omino_str = try omino.toStr();
    std.debug.warn("Omino:\n{s}\n", .{omino_str});
    allocator.free(omino_str);
    
    std.debug.warn("Finished\n", .{});
}
