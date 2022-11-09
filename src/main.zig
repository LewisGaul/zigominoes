const std = @import("std");
const Allocator = std.mem.Allocator;

/// The chosen allocator for this project.
const allocator = std.heap.page_allocator;

/// The 'point' struct.
const Point = struct {
    x: u8,
    y: u8,

    const Self = @This();

    pub fn init(x: u8, y: u8) Self {
        return Self{ .x = x, .y = y };
    }
};

/// The 'omino' struct.
const Omino = struct {
    size: u8,
    points: []Point,

    const Self = @This();

    pub fn init(size: u8, points: []Point) !Self {
        if (size == 0) return error.InvalidSize;
        if (points.len != size) return error.InvalidPoints;

        var self = Self{
            .size = size,
            .points = try allocator.alloc(Point, size),
        };
        // Note: don't bother checking legitimacy of points.
        // Ways they could be invalid/otherwise unconstrained:
        //  - May not be joined up.
        //  - May not be within the '<size>x<size>' grid.
        // Do check for duplicate points, however.
        for (points) |p, i| {
            if (self.hasPoint(p.x, p.y)) return error.DuplicatePoint;
            // This does an implicit copy (reference?).
            self.points[i] = p;
        }
        return self;
    }

    pub fn deinit(self: Self) void {
        allocator.free(self.points);
    }

    pub fn toStr(self: Self) ![]const u8 {
        // TODO: Should use 'std.fmt' or 'std.mem'?
        var bufLen = self.size * (self.size + 1) - 1;
        var buf: []u8 = try allocator.alloc(u8, bufLen);
        var x: u8 = 0;
        var y: u8 = self.size - 1;
        var idx: u8 = 0;

        while (true) {
            x = 0;
            while (x < self.size) {
                buf[idx] = if (self.hasPoint(x, y)) '#' else '.';
                idx += 1;
                x += 1;
            }
            if (y > 0) {
                buf[idx] = '\n';
                idx += 1;
                y -= 1;
            } else {
                break;
            }
        }

        return buf;
    }

    pub fn eql(self: Self, other: Self) bool {
        // Note: can't use std.meta.eql() since it compares slices by pointer.
        if (self.size != other.size) return false;
        for (self.points) |p, i| {
            if (!std.meta.eql(p, other.points[i])) return false;
        }
        return true;
    }

    // Internal functions

    fn hasPoint(self: Self, x: u8, y: u8) bool {
        for (self.points) |*p| {
            if (p.x == x and p.y == y) return true;
        }
        return false;
    }
};

test "omino creation" {
    // Setup.
    var points = [_]Point{
        Point.init(0, 0),
        Point.init(2, 1),
        Point.init(2, 2),
    };
    var omino = try Omino.init(3, &points);
    defer omino.deinit();

    // Success.
    std.testing.expectEqual(@as(u8, 3), omino.size);
    std.testing.expectEqualSlices(Point, &points, omino.points);

    // Errors.
    std.testing.expectError(error.InvalidSize, Omino.init(0, &[_]Point{}));
    std.testing.expectError(error.InvalidPoints, Omino.init(1, &[_]Point{}));
    std.testing.expectError(error.DuplicatePoint, Omino.init(2, &[_]Point{ Point.init(0, 0), Point.init(0, 0) }));
}

test "omino equality" {
    // Setup.
    var points = [_]Point{
        Point.init(0, 0),
        Point.init(2, 1),
        Point.init(2, 2),
    };
    var omino1 = try Omino.init(3, &points);
    var omino2 = try Omino.init(3, &points);
    var omino3 = try Omino.init(1, &[_]Point{Point.init(4, 2)});
    points[0].x = 3;
    var omino4 = try Omino.init(3, &points);
    defer omino1.deinit();
    defer omino2.deinit();
    defer omino3.deinit();
    defer omino4.deinit();

    // Equal to itself.
    std.testing.expect(omino1.eql(omino1));
    std.testing.expect(omino3.eql(omino3));

    // Not equal to another omino of different size.
    std.testing.expect(!omino1.eql(omino3));

    // Not equal to another omino with different contents.
    std.testing.expect(!omino1.eql(omino4));
}

/// Function to create a dummy omino.
/// Returned omino should be freed by the caller.
fn createOmino() !Omino {
    var points = [_]Point{
        Point.init(0, 0),
        Point.init(1, 0),
        Point.init(1, 1),
        Point.init(2, 1),
    };
    var omino = try Omino.init(4, &points);
    return omino;
}

/// Main.
pub fn main() !void {
    std.debug.warn("Running...\n", .{});

    var omino = try createOmino();
    defer omino.deinit();
    std.debug.warn("{}\n", .{omino});
    var omino_str = try omino.toStr();
    std.debug.warn("Omino:\n{s}\n", .{omino_str});
    allocator.free(omino_str); // @@@ Does this guarantee all the memory was freed?

    std.debug.warn("Finished\n", .{});
}
