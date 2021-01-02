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

    pub fn lessThan(self: Self, other: Self) bool {
        if (self.x != other.x) return self.x < other.x;
        if (self.y != other.y) return self.y < other.y;
        return false; // Equal
    }
};

/// A struct representing an unordered set of unique points.
const PointSet = struct {
    // @@@ Not sure whether an array hashmap is a good choice or not.
    // Implicitly not storing the hash, allowing direct mutations.
    hashMap: std.AutoArrayHashMap(Point, void),

    const Self = @This();

    const Iterator = struct {
        hmIt: std.AutoArrayHashMap(Point, void).Iterator,

        pub fn next(it: *Iterator) ?*Point {
            var entry = it.hmIt.next() orelse return null;
            return &entry.key;
        }

        pub fn reset(it: *Iterator) void {
            it.hmIt.reset();
        }
    };

    pub fn init() Self {
        return Self{ .hashMap = std.AutoArrayHashMap(Point, void).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.hashMap.deinit();
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var entries = self.hashMap.items();
        var point: Point = undefined;

        try writer.writeAll(@typeName(Self));
        if (self.hashMap.count() == 0) {
            try writer.writeAll("{}");
            return;
        } else {
            try writer.writeAll("{ ");
            for (entries[0 .. entries.len - 1]) |entry| {
                point = entry.key;
                try writer.print("({}, {}), ", .{ point.x, point.y });
            }
            point = entries[entries.len - 1].key;
            try writer.print("({}, {}) }}", .{ point.x, point.y });
        }
    }

    pub fn put(self: *Self, point: Point) !void {
        try self.hashMap.put(point, {});
    }

    pub fn count(self: Self) usize {
        return self.hashMap.count();
    }

    pub fn contains(self: Self, point: Point) bool {
        return self.hashMap.contains(point);
    }

    pub fn eql(self: Self, other: Self) bool {
        if (self.count() != other.count()) return false;
        for (self.hashMap.items()) |entry| {
            if (!other.contains(entry.key)) return false;
        }
        return true;
    }

    pub fn clone(self: Self) !Self {
        return Self{ .hashMap = try self.hashMap.clone() };
    }

    pub fn lessThan(self: *Self, other: *Self) bool {
        if (self.count() != other.count()) return self.count() < other.count();

        self.sort();
        other.sort();

        for (self.hashMap.items()) |entry, i| {
            if (std.meta.eql(entry.key, other.hashMap.items()[i].key)) continue;
            return entry.key.lessThan(other.hashMap.items()[i].key);
        }
        return false;
    }

    pub fn iterator(self: *const Self) Iterator {
        return Iterator{ .hmIt = self.hashMap.iterator() };
    }

    fn sort(self: *Self) void {
        const Entry = @TypeOf(self.hashMap).Entry;
        const inner = struct {
            pub fn lessThan(context: void, lhs: Entry, rhs: Entry) bool {
                return lhs.key.lessThan(rhs.key);
            }
        };
        std.sort.sort(Entry, self.hashMap.items(), {}, inner.lessThan);
    }
};

/// The 'omino' struct.
const Omino = struct {
    size: u5,
    points: PointSet,

    const Self = @This();

    pub fn init(size: u5, points: []Point) !Self {
        if (size == 0) return error.InvalidSize;
        if (points.len != size) return error.InvalidPoints;

        var self = Self{
            .size = size,
            .points = PointSet.init(),
        };
        // Note: list of points could be 'invalid' in the following ways:
        //  1. Duplicate points
        //       Handled immediately.
        //  2. Points not be joined up
        //       Checked explicitly.
        //  3. Points not be within the '<size>x<size>' grid
        //       Doesn't matter - fixed in canonicalisation.
        for (points) |p, i| {
            if (self.points.contains(p)) return error.DuplicatePoint;
            try self.points.put(p);
        }
        try self.checkJoined();
        try self.canonicalise();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.points.deinit();
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
                if (self.points.contains(Point.init(x, y))) {
                    try writer.writeByte('#');
                } else {
                    try writer.writeByte('.');
                }
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
        if (self.size != other.size) return false;
        return self.points.eql(other.points);
    }

    // Internal functions

    fn checkJoined(self: Self) !void {
        // @@@ Implement.
    }

    fn moveToCorner(self: *Self) void {
        var min_x: u8 = std.math.maxInt(u8);
        var min_y: u8 = std.math.maxInt(u8);

        var iterator = self.points.iterator();
        while (iterator.next()) |p| {
            min_x = std.math.min(min_x, p.x);
            min_y = std.math.min(min_y, p.y);
        }
        iterator.reset();
        while (iterator.next()) |p| {
            p.x -= min_x;
            p.y -= min_y;
        }
    }

    fn rotate(self: *Self) void {
        var iterator = self.points.iterator();
        var newPoint: Point = undefined;
        while (iterator.next()) |p| {
            newPoint = Point{ .x = self.size - p.y - 1, .y = p.x };
            p.* = newPoint;
        }
        // log.debug("Rotated:\n{}\n", .{self});
        self.moveToCorner();
        // log.debug("Cornered:\n{}\n", .{self});
        log.debug("Rotated:\n{}\n", .{self});
    }

    fn transpose(self: *Self) void {
        var iterator = self.points.iterator();
        var newPoint: Point = undefined;
        while (iterator.next()) |p| {
            newPoint = Point{ .x = p.y, .y = p.x };
            p.* = newPoint;
        }
        log.debug("Transposed:\n{}\n", .{self});
    }

    fn canonicalise(self: *Self) !void {
        var minPoints: PointSet = try self.points.clone();

        const inner = struct {
            pub fn checkPoints(curPts: *PointSet, minPts: *PointSet) void {
                if (curPts.lessThan(minPts)) {
                    storePoints(curPts, minPts);
                }
            }

            pub fn storePoints(fromPts: *PointSet, toPts: *PointSet) void {
                var fromIt = fromPts.iterator();
                var toIt = toPts.iterator();
                var toPt = toIt.next();
                while (fromIt.next()) |fromPt| : (toPt = toIt.next()) {
                    toPt.?.* = fromPt.*;
                }
            }
        };

        log.debug("Initial:\n{}\n", .{self});
        self.moveToCorner();
        log.debug("Cornered:\n{}\n", .{self});

        self.rotate();
        inner.checkPoints(&self.points, &minPoints);
        self.rotate();
        inner.checkPoints(&self.points, &minPoints);
        self.rotate();
        inner.checkPoints(&self.points, &minPoints);
        self.transpose();
        inner.checkPoints(&self.points, &minPoints);
        self.rotate();
        inner.checkPoints(&self.points, &minPoints);
        self.rotate();
        inner.checkPoints(&self.points, &minPoints);
        self.rotate();
        inner.checkPoints(&self.points, &minPoints);

        log.debug("Canonical points: {}", .{minPoints});
        self.points.deinit();
        self.points = minPoints;
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

/// Do some testing of Zig functionality!
fn testing() !void {
    log.debug("Doing some Zig testing...", .{});
}

/// Main.
pub fn main() !void {
    log.debug("Running...", .{});

    var omino = try createOmino();
    defer omino.deinit();
    std.debug.print("Omino:\n{}\n\n", .{omino});

    try testing();

    log.debug("Finished", .{});
}
