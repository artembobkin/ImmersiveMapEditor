import Foundation
@testable import Geometry

/// The public API of `Geometry` as the wrapper replay walks it
/// (`Recording/WrapperReplayTests`), so one walk runs on the old wrapper on
/// GEOS (whose answers it stored) and on the new `Geometry` (compared with
/// them). The styles of the buffer and the offset curve are their raw
/// values, as the two wrappers name their enums apart.
protocol WrapperGeometry: AnyObject, CustomStringConvertible {
    associatedtype PreparedType: WrapperPrepared where PreparedType.G == Self
    associatedtype TreeType: WrapperTree where TreeType.G == Self

    static func readWKB(_ wkb: [UInt8]) -> Self
    var wkb: [UInt8] { get }
    var grids: [Double] { get }
    var kindCode: Int32 { get }

    var isEmpty: Bool { get }
    var isMulti: Bool { get }
    var isValid: Bool { get }
    var area: Double { get }
    var length: Double { get }
    var bounds: (Double, Double, Double, Double) { get }
    var xy: P2 { get }
    var coords: [P2] { get }
    var exterior: [P2] { get }
    var interiors: [[P2]] { get }
    var parts: [Self] { get }
    var polygons: [Self] { get }
    var lines: [Self] { get }
    var centroid: Self { get }
    var representativePoint: Self { get }
    var convexHull: Self { get }
    var envelope: Self { get }
    var boundary: Self { get }
    var minimumRotatedRectangle: Self { get }

    static func makePoint(_ p: P2) -> Self
    static func makeLineString(_ pts: [P2]) -> Self
    static func makePolygon(_ shell: [P2], holes: [[P2]]) -> Self
    static func makeCollection(_ parts: [Self]) -> Self
    static func makeUnaryUnion(_ parts: [Self]) -> Self
    static func makePolygonize(_ lines: [Self]) -> Self

    func styledBuffer(_ d: Double, quadSegs: Int, cap: Int32, join: Int32, mitreLimit: Double) -> Self
    func styledOffsetCurve(_ d: Double, quadSegs: Int, join: Int32, mitreLimit: Double) -> Self
    func union(_ o: Self) -> Self
    func intersection(_ o: Self) -> Self
    func difference(_ o: Self) -> Self
    func simplify(_ tolerance: Double) -> Self
    func makeValid() -> Self
    func setPrecision(_ grid: Double) -> Self
    func interpolate(_ d: Double, normalized: Bool) -> Self
    func project(_ p: Self) -> Double
    func distance(_ o: Self) -> Double
    func intersects(_ o: Self) -> Bool
    func contains(_ o: Self) -> Bool
    func within(_ o: Self) -> Bool
    func nearestPoints(_ o: Self) -> (P2, P2)
    func constrainedDelaunay() -> [[P2]]
    func lineMerge() -> Self
    func map(_ f: (P2) -> P2) -> Self
    func rotate(_ angle: Double, origin: P2, radians: Bool) -> Self
    func scale(_ sx: Double, _ sy: Double, origin: P2) -> Self
    func translate(_ dx: Double, _ dy: Double) -> Self
    func oriented(_ sign: Double) -> Self
    func substring(_ start: Double, _ end: Double) -> Self
}

protocol WrapperPrepared {
    associatedtype G
    init(_ g: G)
    func contains(_ o: G) -> Bool
    func intersects(_ o: G) -> Bool
}

protocol WrapperTree {
    associatedtype G
    init(_ items: [G])
    func query(_ g: G) -> [Int]
    func nearest(_ g: G) -> Int?
}

extension Geometry: WrapperGeometry {
    typealias PreparedType = Prepared
    typealias TreeType = STRtree

    static func readWKB(_ wkb: [UInt8]) -> Geometry { try! Geometry.read(wkb: wkb) }
    var kindCode: Int32 { kind.rawValue }

    static func makePoint(_ p: P2) -> Geometry { .point(p) }
    static func makeLineString(_ pts: [P2]) -> Geometry { .lineString(pts) }
    static func makePolygon(_ shell: [P2], holes: [[P2]]) -> Geometry { .polygon(shell, holes: holes) }
    static func makeCollection(_ parts: [Geometry]) -> Geometry { .collection(parts) }
    static func makeUnaryUnion(_ parts: [Geometry]) -> Geometry { .unaryUnion(parts) }
    static func makePolygonize(_ lines: [Geometry]) -> Geometry { .polygonize(lines) }

    func styledBuffer(_ d: Double, quadSegs: Int, cap: Int32, join: Int32, mitreLimit: Double) -> Geometry {
        buffer(d, quadSegs: quadSegs, cap: Cap(rawValue: cap)!, join: Join(rawValue: join)!, mitreLimit: mitreLimit)
    }

    func styledOffsetCurve(_ d: Double, quadSegs: Int, join: Int32, mitreLimit: Double) -> Geometry {
        offsetCurve(d, quadSegs: quadSegs, join: Join(rawValue: join)!, mitreLimit: mitreLimit)
    }
}

extension Prepared: WrapperPrepared {
    typealias G = Geometry
}

extension STRtree: WrapperTree {
    typealias G = Geometry
}
