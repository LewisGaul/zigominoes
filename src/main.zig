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
        // TODO: Should use 'std.fmt' or 'std.mem'?
        var bufLen = self.size * (self.size + 1) - 1;
        var buf: []u8 = try allocator.alloc(u8, bufLen);
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
            if (i < self.size - 1) { buf[pos] = '\n'; pos += 1; }
            i += 1;
        }
        
        return buf;
    }
};

/// Function to create a dummy omino.
/// Returned omino should be deinitialised by the caller.
fn createOmino() !Omino {
    var omino = try Omino.init(4);
    omino.array[2] = true;
    omino.array[5] = true;
    omino.array[6] = true;
    omino.array[7] = true;
    return omino;
}

/// Main.
pub fn main() !void {
    std.debug.warn("Running...\n", .{});
    
    var omino = try createOmino();
    defer omino.deinit();
    var omino_str = try omino.toStr();
    std.debug.warn("Omino:\n{s}\n", .{omino_str});
    allocator.free(omino_str);  // Does this guarantee all the memory was freed?
    
    std.debug.warn("Finished\n", .{});
}
