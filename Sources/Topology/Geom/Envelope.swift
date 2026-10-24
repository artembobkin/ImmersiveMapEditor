import Darwin

/// An axis-aligned rectangle: JTS's `Envelope`, a value. The null envelope
/// (of an empty geometry) has `maxX < minX`.
public struct Envelope: Equatable, CustomStringConvertible, Sendable {
    public private(set) var minX: Double = 0
    public private(set) var maxX: Double = -1
    public private(set) var minY: Double = 0
    public private(set) var maxY: Double = -1

    /// The null envelope.
    public init() {}

    public init(_ x1: Double, _ x2: Double, _ y1: Double, _ y2: Double) {
        if x1 < x2 { minX = x1; maxX = x2 } else { minX = x2; maxX = x1 }
        if y1 < y2 { minY = y1; maxY = y2 } else { minY = y2; maxY = y1 }
    }

    public init(_ p1: Coordinate, _ p2: Coordinate) { self.init(p1.x, p2.x, p1.y, p2.y) }
    public init(_ p: Coordinate) { self.init(p.x, p.x, p.y, p.y) }

    /// Whether the point `q` is in the envelope of the segment `p1`-`p2`.
    public static func intersects(_ p1: Coordinate, _ p2: Coordinate, _ q: Coordinate) -> Bool {
        (q.x >= (p1.x < p2.x ? p1.x : p2.x)) && (q.x <= (p1.x > p2.x ? p1.x : p2.x))
            && (q.y >= (p1.y < p2.y ? p1.y : p2.y)) && (q.y <= (p1.y > p2.y ? p1.y : p2.y))
    }

    /// Whether the envelopes of the segments `p1`-`p2` and `q1`-`q2` meet.
    public static func intersects(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> Bool {
        var minq = javaMin(q1.x, q2.x), maxq = javaMax(q1.x, q2.x)
        var minp = javaMin(p1.x, p2.x), maxp = javaMax(p1.x, p2.x)
        if minp > maxq { return false }
        if maxp < minq { return false }
        minq = javaMin(q1.y, q2.y); maxq = javaMax(q1.y, q2.y)
        minp = javaMin(p1.y, p2.y); maxp = javaMax(p1.y, p2.y)
        if minp > maxq { return false }
        if maxp < minq { return false }
        return true
    }

    public mutating func setToNull() {
        minX = 0; maxX = -1; minY = 0; maxY = -1
    }

    public var isNull: Bool { maxX < minX }
    public var width: Double { isNull ? 0 : maxX - minX }
    public var height: Double { isNull ? 0 : maxY - minY }
    public var diameter: Double { isNull ? 0 : hypot(width, height) }
    public var area: Double { width * height }

    public var minExtent: Double {
        if isNull { return 0 }
        let w = width, h = height
        return w < h ? w : h
    }

    public var maxExtent: Double {
        if isNull { return 0 }
        let w = width, h = height
        return w > h ? w : h
    }

    public mutating func expandToInclude(_ p: Coordinate) { expandToInclude(p.x, p.y) }

    public mutating func expandToInclude(_ x: Double, _ y: Double) {
        if isNull {
            minX = x; maxX = x; minY = y; maxY = y
        } else {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }

    public mutating func expandToInclude(_ o: Envelope) {
        if o.isNull { return }
        if isNull {
            minX = o.minX; maxX = o.maxX; minY = o.minY; maxY = o.maxY
        } else {
            if o.minX < minX { minX = o.minX }
            if o.maxX > maxX { maxX = o.maxX }
            if o.minY < minY { minY = o.minY }
            if o.maxY > maxY { maxY = o.maxY }
        }
    }

    public mutating func expandBy(_ distance: Double) { expandBy(distance, distance) }

    public mutating func expandBy(_ dx: Double, _ dy: Double) {
        if isNull { return }
        minX -= dx; maxX += dx; minY -= dy; maxY += dy
        if minX > maxX || minY > maxY { setToNull() }
    }

    public mutating func translate(_ tx: Double, _ ty: Double) {
        if isNull { return }
        self = Envelope(minX + tx, maxX + tx, minY + ty, maxY + ty)
    }

    /// The centre, nil for the null envelope.
    public var centre: Coordinate? {
        isNull ? nil : Coordinate((minX + maxX) / 2.0, (minY + maxY) / 2.0)
    }

    public func intersection(_ e: Envelope) -> Envelope {
        if isNull || e.isNull || !intersects(e) { return Envelope() }
        let x0 = minX > e.minX ? minX : e.minX
        let y0 = minY > e.minY ? minY : e.minY
        let x1 = maxX < e.maxX ? maxX : e.maxX
        let y1 = maxY < e.maxY ? maxY : e.maxY
        return Envelope(x0, x1, y0, y1)
    }

    public func intersects(_ o: Envelope) -> Bool {
        if isNull || o.isNull { return false }
        return !(o.minX > maxX || o.maxX < minX || o.minY > maxY || o.maxY < minY)
    }

    /// Whether the envelope of the segment `a`-`b` meets this one.
    public func intersects(_ a: Coordinate, _ b: Coordinate) -> Bool {
        if isNull { return false }
        let x0 = (a.x < b.x) ? a.x : b.x
        if x0 > maxX { return false }
        let x1 = (a.x > b.x) ? a.x : b.x
        if x1 < minX { return false }
        let y0 = (a.y < b.y) ? a.y : b.y
        if y0 > maxY { return false }
        let y1 = (a.y > b.y) ? a.y : b.y
        if y1 < minY { return false }
        return true
    }

    public func disjoint(_ o: Envelope) -> Bool { !intersects(o) }
    public func intersects(_ p: Coordinate) -> Bool { intersects(p.x, p.y) }

    public func intersects(_ x: Double, _ y: Double) -> Bool {
        if isNull { return false }
        return !(x > maxX || x < minX || y > maxY || y < minY)
    }

    public func contains(_ o: Envelope) -> Bool { covers(o) }
    public func contains(_ p: Coordinate) -> Bool { covers(p.x, p.y) }

    public func covers(_ x: Double, _ y: Double) -> Bool {
        if isNull { return false }
        return x >= minX && x <= maxX && y >= minY && y <= maxY
    }

    public func covers(_ p: Coordinate) -> Bool { covers(p.x, p.y) }

    public func covers(_ o: Envelope) -> Bool {
        if isNull || o.isNull { return false }
        return o.minX >= minX && o.maxX <= maxX && o.minY >= minY && o.maxY <= maxY
    }

    public func distance(_ e: Envelope) -> Double {
        if intersects(e) { return 0 }
        var dx = 0.0
        if maxX < e.minX { dx = e.minX - maxX } else if minX > e.maxX { dx = minX - e.maxX }
        var dy = 0.0
        if maxY < e.minY { dy = e.minY - maxY } else if minY > e.maxY { dy = minY - e.maxY }
        if dx == 0.0 { return dy }
        if dy == 0.0 { return dx }
        return hypot(dx, dy)
    }

    public static func == (a: Envelope, b: Envelope) -> Bool {
        if a.isNull { return b.isNull }
        return a.maxX == b.maxX && a.maxY == b.maxY && a.minX == b.minX && a.minY == b.minY
    }

    public func compareTo(_ e: Envelope) -> Int {
        if isNull { return e.isNull ? 0 : -1 }
        if e.isNull { return 1 }
        if minX < e.minX { return -1 }
        if minX > e.minX { return 1 }
        if minY < e.minY { return -1 }
        if minY > e.minY { return 1 }
        if maxX < e.maxX { return -1 }
        if maxX > e.maxX { return 1 }
        if maxY < e.maxY { return -1 }
        if maxY > e.maxY { return 1 }
        return 0
    }

    public var description: String { "Env[\(minX) : \(maxX), \(minY) : \(maxY)]" }
}
