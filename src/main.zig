const std = @import("std");
const Allocator = std.mem.Allocator;

/// The chosen allocator for this project.
const allocator = std.heap.page_allocator;
const log = std.log.scoped(.main);
pub const log_level = .debug;

/// The 'point' struct.
const Point = struct {
    x: u8,
    y: u8,

    const Self = @This();

    pub fn init(x: u8, y: u8) Self {
        return Self{ .x = x, .y = y };
    }

    pub fn lessThan(self: Self, other: Self) bool {
        if (self.y != other.y) return self.y < other.y;
        if (self.x != other.x) return self.x < other.x;
        return false; // Equal
    }

    pub fn eql(self: Self, other: Self) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn hash(self: Self) u32 {
        // @@@ Not sure this is suitable...
        return std.array_hash_map.getAutoHashFn(Self)(self);
    }
};

/// A struct representing an unordered set of unique points.
const PointSet = struct {
    // @@@ Not sure whether an array hashmap is a good choice or not.
    hashMap: HashMap,

    const Self = @This();

    // Not storing the hash to allow direct mutations without needing to reindex.
    const HashMap = std.ArrayHashMap(Point, void, Point.hash, Point.eql, false);
    const Iterator = struct {
        hmIt: HashMap.Iterator,

        pub fn next(it: *Iterator) ?*Point {
            var entry = it.hmIt.next() orelse return null;
            return &entry.key;
        }

        pub fn reset(it: *Iterator) void {
            it.hmIt.reset();
        }
    };

    pub fn init() Self {
        return Self{ .hashMap = HashMap.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.hashMap.deinit();
        self.* = undefined;
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
        errdefer self.deinit();
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
        self.* = undefined;
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var x: u8 = undefined;
        var y: u8 = self.size;

        while (true) {
            x = 1;
            while (x <= self.size) {
                if (self.points.contains(Point.init(x, y))) {
                    try writer.writeByte('#');
                } else {
                    try writer.writeByte('.');
                }
                x += 1;
            }
            if (y > 1) {
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

    pub fn hash(self: Self) u64 {
        std.debug.assert(@as(u16, self.size) * (@as(u16, self.size) + 1) <= 512);
        var buffer = [_]u8{0} ** 512;
        var writer = std.io.fixedBufferStream(&buffer).writer();
        writer.print("{}", .{self}) catch unreachable;
        return std.hash_map.hashString(&buffer);
    }

    pub fn lessThan(self: *Self, other: *Self) bool {
        return self.points.lessThan(other.points);
    }

    /// Get the set of surrounding points that can be set to increase the omino
    /// size.
    pub fn getFreeNeighbours(self: Self) !PointSet {
        var nbrs = PointSet.init();
        var newPts: []Point = undefined;
        var iterator = self.points.iterator();
        while (iterator.next()) |p| {
            newPts = &[_]Point{
                Point.init(p.x + 1, p.y),
                Point.init(p.x - 1, p.y),
                Point.init(p.x, p.y + 1),
                Point.init(p.x, p.y - 1),
            };
            for (newPts) |newPt| {
                if (!self.points.contains(newPt)) {
                    try nbrs.put(newPt);
                }
            }
        }
        return nbrs;
    }

    /// Clone the omino and add the given point.
    /// The memory is owned by the caller and should be freed with
    /// 'omino.deinit()'.
    pub fn cloneAddPoint(self: Self, point: Point) !Self {
        var points = std.ArrayList(Point).init(allocator);
        defer points.deinit();
        var iterator = self.points.iterator();
        while (iterator.next()) |p| {
            try points.append(p.*);
        }
        try points.append(point);
        return Self.init(self.size + 1, points.items);
    }

    // Internal functions

    /// Check the points are joined up to form a viable omino.
    fn checkJoined(self: Self) !void {
        // @@@ Implement.
    }

    /// In-place move to bottom-left corner.
    /// Coordinate (1, 1) is the minimum to allow adding points around the
    /// edge.
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
            p.x = p.x + 1 - min_x;
            p.y = p.y + 1 - min_y;
        }
        // log.debug("Cornered:\n{}\n", .{self});
    }

    /// In-place rotate 90 degress anti-clockwise.
    fn rotate(self: *Self) void {
        var iterator = self.points.iterator();
        var newPoint: Point = undefined;
        while (iterator.next()) |p| {
            newPoint = Point{ .x = self.size - p.y, .y = p.x };
            p.* = newPoint;
        }
        // log.debug("Rotated:\n{}\n", .{self});
        self.moveToCorner();
        // log.debug("Cornered:\n{}\n", .{self});
        // log.debug("Rotated:\n{}\n", .{self});
    }

    /// In-place transpose, swapping x and y coordinates.
    fn transpose(self: *Self) void {
        var iterator = self.points.iterator();
        var newPoint: Point = undefined;
        while (iterator.next()) |p| {
            newPoint = Point{ .x = p.y, .y = p.x };
            p.* = newPoint;
        }
        // log.debug("Transposed:\n{}\n", .{self});
    }

    /// In-place transform to canonical representation.
    fn canonicalise(self: *Self) !void {
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

        // log.debug("Initial:\n{}\n", .{self});
        self.moveToCorner();
        // log.debug("Cornered:\n{}\n", .{self});

        var minPoints: PointSet = try self.points.clone();
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

        // log.debug("Canonical points: {}", .{minPoints});
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

/// A struct representing a set of unique ominoes.
const OminoSet = struct {
    ominoSize: u5,
    hashMap: HashMap,

    const Self = @This();

    const HashMap = std.HashMap(
        Omino,
        void,
        Omino.hash,
        Omino.eql,
        std.hash_map.DefaultMaxLoadPercentage,
    );
    const Iterator = struct {
        hmIt: HashMap.Iterator,

        pub fn next(it: *Iterator) ?*Omino {
            var entry = it.hmIt.next() orelse return null;
            return &entry.key;
        }
    };

    pub fn init(ominoSize: u5) Self {
        return Self{
            .ominoSize = ominoSize,
            .hashMap = HashMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.hashMap.deinit();
        self.* = undefined;
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Set of {d} {d}-ominoes:\n", .{ self.hashMap.count(), self.ominoSize });
        var it = self.iterator();
        while (it.next()) |om| {
            try writer.print("{}\n--------\n", .{om});
        }
    }

    pub fn contains(self: Self, omino: Omino) bool {
        return self.hashMap.contains(omino);
    }

    pub fn count(self: Self) u64 {
        return self.hashMap.count();
    }

    pub fn put(self: *Self, omino: Omino) !void {
        try self.hashMap.put(omino, {});
    }

    pub fn iterator(self: *const Self) Iterator {
        return Iterator{ .hmIt = self.hashMap.iterator() };
    }

    pub fn addByOminoGrowth(self: *Self, omino: *Omino) !void {
        var it = (try omino.getFreeNeighbours()).iterator();
        while (it.next()) |p| {
            try self.put(try omino.cloneAddPoint(p.*));
        }
    }
};

/// The initial set of ominoes.
fn initialOminoSet() !OminoSet {
    var oneOmino = try Omino.init(1, &[_]Point{Point.init(0, 0)});
    var ominoSet = OminoSet.init(1);
    try ominoSet.put(oneOmino);
    return ominoSet;
}

/// Do some testing of Zig functionality!
fn testing() !void {
    log.debug("Doing some Zig testing...", .{});
}

/// Main.
pub fn main() !void {
    log.debug("Running...", .{});

    var prevSet = try initialOminoSet();
    var nextSet: @TypeOf(prevSet) = undefined;
    var omIterator: @TypeOf(prevSet).Iterator = undefined;

    std.debug.print("{}", .{prevSet});
    while (prevSet.ominoSize < std.math.maxInt(u5)) {
        nextSet = OminoSet.init(prevSet.ominoSize + 1);
        omIterator = prevSet.iterator();
        while (omIterator.next()) |om| {
            try nextSet.addByOminoGrowth(om);
        }
        if (nextSet.ominoSize <= 5) {
            std.debug.print("{}", .{nextSet});
        } else {
            std.debug.print("Found {d} {d}-ominoes\n", .{ nextSet.count(), nextSet.ominoSize });
        }
        prevSet.deinit();
        prevSet = nextSet;
        nextSet = undefined;
    }
    prevSet.deinit();

    // try testing();

    log.debug("Finished", .{});
}
