const std = @import("std");
const Allocator = std.mem.Allocator;

/// The chosen allocator for this project.
const allocator = std.heap.page_allocator;
const log = std.log.scoped(.main);
const log_level = .debug;

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
    size: u5,
    points: []Point,

    const Self = @This();

    pub fn init(size: u5, points: []Point) !Self {
        if (size == 0) return error.InvalidSize;
        if (points.len != size) return error.InvalidPoints;

        var self = Self{
            .size = size,
            .points = try allocator.alloc(Point, size),
        };
        // Note: list of points could be 'invalid' in the following ways:
        //  1. Duplicate points
        //       Handled immediately.
        //  2. Points not be joined up
        //       Caught in canonicalisation.
        //  3. Points not be within the '<size>x<size>' grid
        //       Doesn't matter - fixed in canonicalisation.
        for (points) |p, i| {
            if (self.hasPoint(p.x, p.y)) return error.DuplicatePoint;
            // This does an implicit copy (@@@ docs reference?).
            self.points[i] = p;
        }
        try self.canonicalise();
        return self;
    }

    pub fn deinit(self: Self) void {
        allocator.free(self.points);
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var x: u8 = undefined;
        var y: u8 = self.size - 1;

        while (true) {
            x = 0;
            while (x < self.size) {
                try writer.writeByte(if (self.hasPoint(x, y)) '#' else '.');
                x += 1;
            }
            if (y > 0) {
                try writer.writeByte('\n');
                y -= 1;
            } else {
                break;
            }
        }
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

    fn moveToCorner(self: Self) void {
        var min_x: u8 = std.math.maxInt(u8);
        var min_y: u8 = std.math.maxInt(u8);

        for (self.points) |p| {
            min_x = std.math.min(min_x, p.x);
            min_y = std.math.min(min_y, p.y);
        }
        for (self.points) |*p| {
            p.x -= min_x;
            p.y -= min_y;
        }
    }

    fn signatureValue(self: Self) u256 {
        // @@@ In theory this could overflow for size > 8...
        var result: u256 = 0;
        for (self.points) |p| {
            result += @as(u256, 1) << (p.x + p.y * self.size);
        }
        return result;
    }

    fn savePoints(self: Self, points: []Point) void {
        for (self.points) |p, i| {
            points[i] = p;
        }
    }

    fn rotate(self: Self) void {
        for (self.points) |p, i| {
            self.points[i] = Point{ .x = self.size - p.y - 1, .y = p.x };
        }
        log.debug("Rotated:\n{}\n", .{self});
        self.moveToCorner();
        log.debug("Cornered:\n{}\n", .{self});
    }

    fn transpose(self: Self) void {
        for (self.points) |p, i| {
            self.points[i] = Point{ .x = p.y, .y = p.x };
        }
        log.debug("Transposed:\n{}\n", .{self});
    }

    fn canonicalise(self: Self) !void {
        // @@@ Check joined.
        log.debug("Initial:\n{}\n", .{self});
        self.moveToCorner();
        log.debug("Cornered:\n{}\n", .{self});

        var points = try allocator.alloc(Point, self.size);
        defer allocator.free(points);
        var signature: u256 = self.signatureValue();
        self.savePoints(points);

        self.rotate();
        if (self.signatureValue() < signature) {
            signature = self.signatureValue();
            self.savePoints(points);
        }
        self.rotate();
        if (self.signatureValue() < signature) {
            signature = self.signatureValue();
            self.savePoints(points);
        }
        self.rotate();
        if (self.signatureValue() < signature) {
            signature = self.signatureValue();
            self.savePoints(points);
        }
        self.transpose();
        if (self.signatureValue() < signature) {
            signature = self.signatureValue();
            self.savePoints(points);
        }
        self.rotate();
        if (self.signatureValue() < signature) {
            signature = self.signatureValue();
            self.savePoints(points);
        }
        self.rotate();
        if (self.signatureValue() < signature) {
            signature = self.signatureValue();
            self.savePoints(points);
        }
        self.rotate();
        if (self.signatureValue() < signature) {
            signature = self.signatureValue();
            self.savePoints(points);
        }

        // @@@ This would be more efficient:
        // var points = pointsFromSignature(signature);
        for (points) |p, i| {
            self.points[i] = p;
        }
    }
};

test "omino creation" {
    // Setup.
    var points = [_]Point{
        Point.init(0, 1),
        Point.init(2, 1),
        Point.init(2, 2),
    };
    var omino = try Omino.init(3, &points);
    defer omino.deinit();

    // Success.
    std.testing.expectEqual(@as(u8, 3), omino.size);
    // @@@ Depends on the order, which is not currently well-defined.
    std.testing.expectEqualSlices(Point, omino.points, &[_]Point{ Point.init(2, 0), Point.init(0, 0), Point.init(0, 1) });

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
        Point.init(2, 2),
        Point.init(3, 1),
        Point.init(4, 3),
        Point.init(3, 3),
        Point.init(3, 2),
    };
    var omino = try Omino.init(5, &points);
    return omino;
}

/// Main.
pub fn main() !void {
    log.debug("Running...", .{});

    var omino = try createOmino();
    defer omino.deinit();
    std.debug.print("Omino:\n{}\n\n", .{omino});

    log.debug("Finished", .{});
}
