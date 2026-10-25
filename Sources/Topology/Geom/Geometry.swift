/// A planar geometry: JTS's `Geometry`, the base of `Point`, `LineString`,
/// `LinearRing`, `Polygon` and the collections. Methods keep JTS's names, so
/// the port reads side by side with it. A geometry is a class, as in JTS:
/// `normalize` changes it in place, `copy` makes an independent one.
///
/// The subclasses are only those of this module: what JTS declares abstract
/// traps here if a subclass forgets it.
public class Geometry: CustomStringConvertible {
    /// The type codes, in the order geometries of different types compare.
    enum TypeCode: Int {
        case point = 0, multiPoint, lineString, linearRing, multiLineString, polygon, multiPolygon, geometryCollection
    }

    public let factory: GeometryFactory
    /// The envelope, computed once.
    @exclusivity(unchecked) var envelopeCache: Envelope?
    @exclusivity(unchecked) public var userData: Any?

    init(factory: GeometryFactory) {
        self.factory = factory
    }

    var typeCode: TypeCode { fatalError("abstract") }
    public func getGeometryType() -> String { fatalError("abstract") }
    public func getCoordinate() -> Coordinate? { fatalError("abstract") }
    public func getCoordinates() -> [Coordinate] { fatalError("abstract") }
    public func getNumPoints() -> Int { fatalError("abstract") }
    public func isEmpty() -> Bool { fatalError("abstract") }
    public func getDimension() -> Int { fatalError("abstract") }
    public func getBoundaryDimension() -> Int { fatalError("abstract") }
    public func getBoundary() -> Geometry { fatalError("abstract") }
    public func equalsExact(_ other: Geometry, tolerance: Double) -> Bool { fatalError("abstract") }
    public func normalize() { fatalError("abstract") }
    func computeEnvelopeInternal() -> Envelope { fatalError("abstract") }
    func compareToSameClass(_ other: Geometry) -> Int { fatalError("abstract") }
    func copyInternal() -> Geometry { fatalError("abstract") }
    func reverseInternal() -> Geometry { fatalError("abstract") }

    /// Every component, this geometry first (JTS's `GeometryComponentFilter`).
    public func applyComponents(_ f: (Geometry) -> Void) { f(self) }
    /// Every geometry, collections and their members (`GeometryFilter`).
    public func applyGeometries(_ f: (Geometry) -> Void) { f(self) }

    public func getNumGeometries() -> Int { 1 }
    public func getGeometryN(_ n: Int) -> Geometry { self }
    public var precisionModel: PrecisionModel { factory.precisionModel }

    public func hasDimension(_ dim: Int) -> Bool { dim == getDimension() }
    public func isRectangle() -> Bool { false }
    public func getArea() -> Double { 0.0 }
    public func getLength() -> Double { 0.0 }

    public func getEnvelopeInternal() -> Envelope {
        if let e = envelopeCache { return e }
        let e = computeEnvelopeInternal()
        envelopeCache = e
        return e
    }

    public func getEnvelope() -> Geometry { factory.toGeometry(getEnvelopeInternal()) }

    /// Forgets the cached envelope after the coordinates changed.
    public func geometryChanged() { applyComponents { $0.envelopeCache = nil } }

    public func getCentroid() -> Point {
        if isEmpty() { return factory.createPoint() }
        return createPointFromInternalCoord(Centroid.getCentroid(self))
    }

    public func getInteriorPoint() -> Point {
        if isEmpty() { return factory.createPoint() }
        return createPointFromInternalCoord(InteriorPoint.getInteriorPoint(self))
    }

    public func convexHull() -> Geometry { ConvexHull(self).getConvexHull() }

    func createPointFromInternalCoord(_ c: Coordinate?) -> Point {
        guard let c else { return factory.createPoint() }
        return factory.createPoint(precisionModel.makePrecise(c))
    }

    public func equalsExact(_ other: Geometry) -> Bool { self === other || equalsExact(other, tolerance: 0) }

    public func equalsNorm(_ g: Geometry) -> Bool { norm().equalsExact(g.norm()) }

    func isEquivalentClass(_ other: Geometry) -> Bool { type(of: self) == type(of: other) }

    func equal(_ a: Coordinate, _ b: Coordinate, _ tolerance: Double) -> Bool {
        if tolerance == 0 { return a == b }
        return a.distance(b) <= tolerance
    }

    public func copy() -> Geometry {
        let c = copyInternal()
        c.envelopeCache = envelopeCache
        c.userData = userData
        return c
    }

    /// A normalized copy.
    public func norm() -> Geometry {
        let c = copy()
        c.normalize()
        return c
    }

    public func reverse() -> Geometry {
        let r = reverseInternal()
        r.envelopeCache = envelopeCache
        return r
    }

    public func compareTo(_ other: Geometry) -> Int {
        if typeCode != other.typeCode { return typeCode.rawValue - other.typeCode.rawValue }
        if isEmpty() && other.isEmpty() { return 0 }
        if isEmpty() { return -1 }
        if other.isEmpty() { return 1 }
        return compareToSameClass(other)
    }

    var isGeometryCollection: Bool { typeCode == .geometryCollection }

    public var description: String { WKTWriter().write(self) }
}
