const std = @import("std");
const Allocator = std.mem.Allocator;

/// The chosen allocator for this project.
const allocator = std.heap.page_allocator;

/// The 'omino' struct.
const Omino = struct {
    size: u8,
    array: []bool,

    const Self = @This();

    pub fn init(size: u8) !Self {
        if (size == 0) return error.InvalidSize;
        var self = Self {
            .size = size,
            .array = try allocator.alloc(bool, size*size),
        };
        for (self.array) |*b| b.* = false;
        return self;
    }

    pub fn deinit(self: Self) void {
        allocator.free(self.array);
    }

    pub fn toStr(self: Self) ![]const u8 {
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

    pub fn eql(self: Self, other: Self) bool {
        // Can't use std.meta.eql() since it compares slices by pointer.
        if (self.size != other.size) return false;
        for (self.array) |elem, i| {
            if (elem != other.array[i]) return false;
        }
        return true;
    }

    // Bottom left is (0, 0), omino lives in positive quadrant.
    pub fn get(self: Self, x: u8, y: u8) bool {
        return self.array[self.getIndex(x, y)];
    }

    pub fn set(self: Self, x: u8, y: u8) void {
        self.array[self.getIndex(x, y)] = true;
    }

    pub fn unset(self: Self, x: u8, y: u8) void {
        self.array[self.getIndex(x, y)] = false;
    }

    // Internal functions

    fn getIndex(self: Self, x: u8, y: u8) u8 {
        return (self.size - y - 1) * self.size + x;
    }
};

test "omino creation" {
    var omino = try Omino.init(3);
    defer omino.deinit();
    std.testing.expectEqual(@as(u8, 3), omino.size);
    std.testing.expectEqualSlices(bool, &[_]bool{false} ** 9, omino.array);
    std.testing.expectError(error.InvalidSize, Omino.init(0));
}

test "omino equality" {
    var omino1 = try Omino.init(3);
    var omino2 = try Omino.init(3);
    var omino3 = try Omino.init(1);
    defer omino1.deinit();
    defer omino2.deinit();
    defer omino3.deinit();
    // Equal to itself.
    std.testing.expect(omino1.eql(omino1));
    std.testing.expect(omino3.eql(omino3));
    // Equal to another empty omino of same size.
    std.testing.expectEqualSlices(bool, omino1.array, omino2.array);
    std.testing.expect(omino1.eql(omino2));
    std.testing.expect(omino2.eql(omino1));
    // Not equal to another omino of different size.
    std.testing.expect(!omino1.eql(omino3));
    // Not equal to another omino with different contents.
    omino1.set(2, 0);
    omino1.set(0, 1);
    std.testing.expect(omino1.eql(omino1));
    std.testing.expect(!omino1.eql(omino2));
    // Equal to another omino with same contents.
    omino2.set(2, 0);
    omino2.set(0, 1);
    std.testing.expect(omino1.eql(omino2));
}

/// Function to create a dummy omino.
/// Returned omino should be freed by the caller.
fn createOmino() !Omino {
    var omino = try Omino.init(4);
    omino.set(0, 1);
    omino.set(0, 0);
    omino.set(1, 0);
    omino.set(2, 0);
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
