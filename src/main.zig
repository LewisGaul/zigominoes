const std = @import("std");

/// The chosen allocator for this project.
const allocator: *std.mem.Allocator = std.testing.allocator;
const log = std.log.scoped(.main);
pub const log_level = .debug;

/// A struct representing an (x, y) coordinate in the positive quadrant.
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
    hash_map: HashMap,

    const Self = @This();

    // @@@ Not sure whether an array hashmap is a good choice or not.
    // Not storing the hash to allow direct mutations without needing to reindex.
    const HashMap = std.ArrayHashMap(Point, void, Point.hash, Point.eql, false);
    const Iterator = struct {
        hm_iter: HashMap.Iterator,

        pub fn next(it: *Iterator) ?*Point {
            return if (it.hm_iter.next()) |entry| &entry.key else null;
        }

        pub fn reset(it: *Iterator) void {
            it.hm_iter.reset();
        }
    };

    pub fn init() Self {
        return Self{ .hash_map = HashMap.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.hash_map.deinit();
        self.* = undefined;
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var entries = self.hash_map.items();
        var point: Point = undefined;

        try writer.writeAll(@typeName(Self));
        if (self.hash_map.count() == 0) {
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
        try self.hash_map.put(point, {});
    }

    pub fn count(self: Self) usize {
        return self.hash_map.count();
    }

    pub fn contains(self: Self, point: Point) bool {
        return self.hash_map.contains(point);
    }

    pub fn eql(self: Self, other: Self) bool {
        if (self.count() != other.count()) return false;
        for (self.hash_map.items()) |entry| {
            if (!other.contains(entry.key)) return false;
        }
        return true;
    }

    // @@@ Both sets must first be sorted to get a meaningful result (be
    //     independent of insertion order).
    pub fn lessThan(self: Self, other: Self) bool {
        if (self.count() != other.count()) return self.count() < other.count();
        for (self.hash_map.items()) |entry, i| {
            if (std.meta.eql(entry.key, other.hash_map.items()[i].key)) continue;
            return entry.key.lessThan(other.hash_map.items()[i].key);
        }
        return false;
    }

    pub fn clone(self: Self) !Self {
        return Self{ .hash_map = try self.hash_map.clone() };
    }

    pub fn iterator(self: *const Self) Iterator {
        return Iterator{ .hm_iter = self.hash_map.iterator() };
    }

    pub fn sort(self: *Self) void {
        const Entry = @TypeOf(self.hash_map).Entry;
        const inner = struct {
            pub fn lessThan(context: void, lhs: Entry, rhs: Entry) bool {
                return lhs.key.lessThan(rhs.key);
            }
        };
        std.sort.sort(Entry, self.hash_map.items(), {}, inner.lessThan);
    }
};

/// A struct representing a single 'omino'.
///
/// An omino has a size and a set of points that correspond to squares.
/// Examples:
///  - Dominoes (2-ominoes): There is only one of these, two squares joined
///  - Tetrominoes (4-ominoes): Tetris blocks
///  - The board game 'Blokus' has all ominoes up to size 5
///  - The single 1-omino is just a single square
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

    pub fn hash(self: Self) u32 {
        std.debug.assert(@as(u16, self.size) * (@as(u16, self.size) + 1) <= 512);
        var buffer = [_]u8{0} ** 512;
        var writer = std.io.fixedBufferStream(&buffer).writer();
        writer.print("{}", .{self}) catch unreachable;
        return std.array_hash_map.hashString(&buffer);
    }

    pub fn lessThan(self: Self, other: Self) bool {
        // Relies on the underlying points sets being sorted, but this is done
        // in canonicalisation.
        return self.points.lessThan(other.points);
    }

    /// Get the set of surrounding points that can be set to increase the omino
    /// size.
    pub fn getFreeNeighbours(self: Self) !PointSet {
        var nbrs = PointSet.init();
        var new_pts: []Point = undefined;
        var iterator = self.points.iterator();
        while (iterator.next()) |p| {
            new_pts = &[_]Point{
                Point.init(p.x + 1, p.y),
                Point.init(p.x - 1, p.y),
                Point.init(p.x, p.y + 1),
                Point.init(p.x, p.y - 1),
            };
            for (new_pts) |new_pt| {
                if (!self.points.contains(new_pt)) {
                    try nbrs.put(new_pt);
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
        var new_pt: Point = undefined;
        while (iterator.next()) |p| {
            new_pt = Point{ .x = self.size - p.y, .y = p.x };
            p.* = new_pt;
        }
        // log.debug("Rotated:\n{}\n", .{self});
        self.moveToCorner();
        // log.debug("Cornered:\n{}\n", .{self});
        // log.debug("Rotated:\n{}\n", .{self});
    }

    /// In-place transpose, swapping x and y coordinates.
    fn transpose(self: *Self) void {
        var iterator = self.points.iterator();
        var new_pt: Point = undefined;
        while (iterator.next()) |p| {
            new_pt = Point{ .x = p.y, .y = p.x };
            p.* = new_pt;
        }
        // log.debug("Transposed:\n{}\n", .{self});
    }

    /// In-place transform to canonical representation.
    fn canonicalise(self: *Self) !void {
        const inner = struct {
            pub fn checkPoints(cur_pts: *PointSet, min_pts: *PointSet) void {
                cur_pts.sort();
                if (cur_pts.lessThan(min_pts.*)) {
                    storePoints(cur_pts.*, min_pts);
                }
            }

            pub fn storePoints(from_pts: PointSet, to_pts: *PointSet) void {
                var from_iter = from_pts.iterator();
                var to_iter = to_pts.iterator();
                var to_pt = to_iter.next();
                while (from_iter.next()) |from_pt| : (to_pt = to_iter.next()) {
                    to_pt.?.* = from_pt.*;
                }
            }
        };

        // log.debug("Initial:\n{}\n", .{self});
        self.moveToCorner();
        self.points.sort();
        // log.debug("Cornered:\n{}\n", .{self});

        var min_points: PointSet = try self.points.clone();
        self.rotate();
        inner.checkPoints(&self.points, &min_points);
        self.rotate();
        inner.checkPoints(&self.points, &min_points);
        self.rotate();
        inner.checkPoints(&self.points, &min_points);
        self.transpose();
        inner.checkPoints(&self.points, &min_points);
        self.rotate();
        inner.checkPoints(&self.points, &min_points);
        self.rotate();
        inner.checkPoints(&self.points, &min_points);
        self.rotate();
        inner.checkPoints(&self.points, &min_points);

        // log.debug("Canonical points: {}", .{min_points});
        self.points.deinit();
        self.points = min_points;
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
    omino_size: u5,
    hash_map: HashMap,

    const Self = @This();

    const HashMap = std.ArrayHashMap(
        Omino,
        void,
        Omino.hash,
        Omino.eql,
        false,
    );
    const Iterator = struct {
        hm_iter: HashMap.Iterator,

        pub fn next(it: *Iterator) ?*Omino {
            return if (it.hm_iter.next()) |entry| &entry.key else null;
        }
    };

    pub fn init(omino_size: u5) Self {
        return Self{
            .omino_size = omino_size,
            .hash_map = HashMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.hash_map.deinit();
        self.* = undefined;
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Set of {d} {d}-ominoes:\n", .{ self.hash_map.count(), self.omino_size });
        var it = self.iterator();
        while (it.next()) |om| {
            try writer.print("{}\n--------\n", .{om});
        }
    }

    pub fn contains(self: Self, omino: Omino) bool {
        return self.hash_map.contains(omino);
    }

    pub fn count(self: Self) u64 {
        return self.hash_map.count();
    }

    pub fn put(self: *Self, omino: Omino) !void {
        try self.hash_map.put(omino, {});
    }

    pub fn iterator(self: *const Self) Iterator {
        return Iterator{ .hm_iter = self.hash_map.iterator() };
    }

    pub fn addByOminoGrowth(self: *Self, omino: *Omino) !void {
        var it = (try omino.getFreeNeighbours()).iterator();
        while (it.next()) |p| {
            try self.put(try omino.cloneAddPoint(p.*));
        }
    }

    pub fn sort(self: *Self) void {
        const Entry = @TypeOf(self.hash_map).Entry;
        const inner = struct {
            pub fn lessThan(context: void, lhs: Entry, rhs: Entry) bool {
                return lhs.key.lessThan(rhs.key);
            }
        };
        std.sort.sort(Entry, self.hash_map.items(), {}, inner.lessThan);
    }
};

/// The initial seed set of ominoes.
fn initialOminoSet() !OminoSet {
    var one_omino = try Omino.init(1, &[_]Point{Point.init(0, 0)});
    var omino_set = OminoSet.init(1);
    try omino_set.put(one_omino);
    return omino_set;
}

/// Do some testing of Zig functionality!
fn testing() !void {
    log.debug("Doing some Zig testing...", .{});
}

/// Main.
pub fn main() !void {
    log.debug("Running...", .{});

    var prev_set = try initialOminoSet();
    var next_set: @TypeOf(prev_set) = undefined;
    var om_iter: @TypeOf(prev_set).Iterator = undefined;

    std.debug.print("{}", .{prev_set});
    while (prev_set.omino_size < std.math.maxInt(u5)) {
        next_set = OminoSet.init(prev_set.omino_size + 1);
        om_iter = prev_set.iterator();
        while (om_iter.next()) |om| {
            try next_set.addByOminoGrowth(om);
        }
        if (next_set.omino_size <= 5) {
            next_set.sort();
            std.debug.print("{}", .{next_set});
        } else {
            std.debug.print("Found {d} {d}-ominoes\n", .{ next_set.count(), next_set.omino_size });
        }
        prev_set.deinit();
        prev_set = next_set;
        next_set = undefined;
    }
    prev_set.deinit();

    // try testing();

    log.debug("Finished", .{});
}
