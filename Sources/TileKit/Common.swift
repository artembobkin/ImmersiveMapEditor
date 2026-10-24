import Foundation
import Geometry
import simd

/// What the build shares: the tile's projection, the OSM data turned into
/// shapes in local metres, small tag readers.
///
/// Local metres: X east and Y north from the tile's Mercator centre, at the
/// Mercator scale of that latitude, the way the engine's baker places a
/// model (TilePipeline's CLAUDE.md, "Fitting the engine").

public let tileExtent = 4096.0
public let earthCircumference = 40075016.686

public func latitudeOfRow(_ row: Double, _ z: Int) -> Double {
    atan(sinh(.pi * (1 - 2 * row / pow(2, Double(z))))) * 180 / .pi
}

/// Longitude and latitude of a point in global tile units at zoom z.
public func mercatorLonLat(_ z: Int, _ gx: Double, _ gy: Double) -> (Double, Double) {
    let n = pow(2, Double(z)) * tileExtent
    return (gx / n * 360 - 180, atan(sinh(.pi * (1 - 2 * gy / n))) * 180 / .pi)
}

/// Anything that turns latitude and longitude into local metres and back.
public protocol Projecting {
    var z: Int { get }
    var folder: URL { get }
    func metres(lat: Double, lon: Double) -> P2
    func lonLat(_ p: P2) -> (Double, Double)
}

/// A fetched tile (data/<z>_<x>_<y>/tile.json): its projection around its
/// own Mercator centre.
public final class Tile: Projecting {
    public let z, x, y: Int
    public let unitsPerMetre: Double
    public let size: Double
    public let folder: URL
    public let info: [String: Any]

    public init(folder: URL) throws {
        let data = try Data(contentsOf: folder.appendingPathComponent("tile.json"))
        info = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let t = info["tile"] as? [String: Int] ?? [:]
        z = t["z"] ?? 15
        x = t["x"] ?? 0
        y = t["y"] ?? 0
        unitsPerMetre = info["units_per_metre"] as? Double ?? 1
        size = info["size_m"] as? Double ?? 0
        self.folder = folder
    }

    public var centreLatitude: Double { ((info["centre"] as? [String: Double]) ?? [:])["latitude"] ?? 0 }
    public var centreLongitude: Double { ((info["centre"] as? [String: Double]) ?? [:])["longitude"] ?? 0 }

    public func metres(lat: Double, lon: Double) -> P2 {
        let n = pow(2, Double(z)) * tileExtent
        let mx = (lon + 180) / 360 * n - Double(x) * tileExtent
        let my = (1 - asinh(tan(lat * .pi / 180)) / .pi) / 2 * n - Double(y) * tileExtent
        return P2((mx - tileExtent / 2) / unitsPerMetre, (tileExtent / 2 - my) / unitsPerMetre)
    }

    public func lonLat(_ p: P2) -> (Double, Double) {
        mercatorLonLat(z, Double(x) * tileExtent + tileExtent / 2 + p.x * unitsPerMetre,
                       Double(y) * tileExtent + tileExtent / 2 - p.y * unitsPerMetre)
    }

    public var bounds: Geometry {
        let h = size / 2
        return .box(-h, -h, h, h)
    }
}

/// A range of tiles projected as one: local metres around the range's
/// Mercator centre, at the Mercator scale of that latitude.
public final class Region: Projecting {
    public let z, x0, y0, x1, y1: Int
    public var folder: URL
    public let gx, gy, unitsPerMetre: Double

    public init(z: Int, x0: Int, y0: Int, x1: Int, y1: Int, folder: URL = URL(fileURLWithPath: "/")) {
        self.z = z
        self.x0 = min(x0, x1); self.x1 = max(x0, x1)
        self.y0 = min(y0, y1); self.y1 = max(y0, y1)
        self.folder = folder
        gx = Double(self.x0 + self.x1 + 1) / 2 * tileExtent
        gy = Double(self.y0 + self.y1 + 1) / 2 * tileExtent
        let lat = latitudeOfRow(Double(self.y0 + self.y1 + 1) / 2, z)
        unitsPerMetre = tileExtent * pow(2, Double(z)) / (earthCircumference * cos(lat * .pi / 180))
    }

    public var name: String { "\(z)_\(x0)_\(y0)_\(x1)_\(y1)" }

    public var tiles: [(Int, Int)] { (y0...y1).flatMap { y in (x0...x1).map { ($0, y) } } }

    public func metres(lat: Double, lon: Double) -> P2 {
        let n = pow(2, Double(z)) * tileExtent
        let mx = (lon + 180) / 360 * n
        let my = (1 - asinh(tan(lat * .pi / 180)) / .pi) / 2 * n
        return P2((mx - gx) / unitsPerMetre, (gy - my) / unitsPerMetre)
    }

    public func lonLat(_ p: P2) -> (Double, Double) {
        mercatorLonLat(z, gx + p.x * unitsPerMetre, gy - p.y * unitsPerMetre)
    }

    public var bounds: Geometry {
        let u = unitsPerMetre
        return .box((Double(x0) * tileExtent - gx) / u, (gy - Double(y1 + 1) * tileExtent) / u,
                    (Double(x1 + 1) * tileExtent - gx) / u, (gy - Double(y0) * tileExtent) / u)
    }
}

// MARK: Tags

public typealias Tags = [String: String]

/// A length tag in metres: "12", "12.5 m", "12,5". nil if unreadable.
public func length(_ value: String?) -> Double? {
    guard var text = value?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
    text = text.replacingOccurrences(of: ",", with: ".")
    for unit in ["m", "meters", "metres"] where text.hasSuffix(unit) {
        text = String(text.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
    }
    guard let n = Double(text), n.isFinite else { return nil }
    return n
}

/// Where a building or part starts above the ground, metres.
public func minHeight(_ tags: Tags) -> Double {
    if let h = length(tags["min_height"]) { return h }
    if let level = length(tags["building:min_level"]) { return level * 3.4 }
    return 0
}

public func underground(_ tags: Tags) -> Bool {
    let layer = length(tags["layer"])
    return tags["location"] == "underground" || tags["indoor"] != nil || (layer.map { $0 < 0 } ?? false)
}

/// A choice that stays the same for the same element on every run: by the
/// CRC-32 of its text, as the Python build chose (zlib.crc32 of str()).
public func stable<T>(_ value: String, _ choices: [T]) -> T {
    choices[Int(crc32(Array(value.utf8)) % UInt32(choices.count))]
}

let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
    var c = UInt32(n)
    for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
}

public func crc32(_ bytes: [UInt8], _ start: UInt32 = 0) -> UInt32 {
    var c = ~start
    for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
    return ~c
}

// MARK: OSM

public struct OsmNode {
    public let id: Int64
    public let lat, lon: Double
    public let tags: Tags
}

public struct OsmWay {
    public let id: Int64
    public let nodes: [Int64]
    public let tags: Tags
}

public struct OsmMember {
    public let type: String
    public let ref: Int64
    public let role: String
}

public struct OsmRelation {
    public let id: Int64
    public let members: [OsmMember]
    public let tags: Tags
}

/// The fetched elements (osm.json in the projection's folder) as shapes in
/// local metres, in the file's order.
public final class Osm {
    public let projection: Projecting
    public private(set) var nodes: [Int64: OsmNode] = [:]
    public private(set) var nodeOrder: [Int64] = []
    public private(set) var ways: [Int64: OsmWay] = [:]
    public private(set) var wayOrder: [Int64] = []
    public private(set) var relations: [OsmRelation] = []
    private var points: [Int64: P2] = [:]

    public init(_ projection: Projecting) throws {
        self.projection = projection
        let data = try Data(contentsOf: projection.folder.appendingPathComponent("osm.json"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        for case let e as [String: Any] in root["elements"] as? [Any] ?? [] {
            guard let type = e["type"] as? String, let id = (e["id"] as? NSNumber)?.int64Value else { continue }
            let tags = e["tags"] as? Tags ?? [:]
            switch type {
            case "node":
                nodes[id] = OsmNode(id: id, lat: (e["lat"] as? NSNumber)?.doubleValue ?? 0,
                                    lon: (e["lon"] as? NSNumber)?.doubleValue ?? 0, tags: tags)
                nodeOrder.append(id)
            case "way":
                ways[id] = OsmWay(id: id, nodes: (e["nodes"] as? [NSNumber] ?? []).map(\.int64Value), tags: tags)
                wayOrder.append(id)
            case "relation":
                let members = (e["members"] as? [[String: Any]] ?? []).map {
                    OsmMember(type: $0["type"] as? String ?? "", ref: ($0["ref"] as? NSNumber)?.int64Value ?? 0,
                              role: $0["role"] as? String ?? "")
                }
                relations.append(OsmRelation(id: id, members: members, tags: tags))
            default:
                break
            }
        }
    }

    public func point(_ node: Int64) -> P2 {
        if let p = points[node] { return p }
        let n = nodes[node]!
        let p = projection.metres(lat: n.lat, lon: n.lon)
        points[node] = p
        return p
    }

    public func wayCoords(_ way: OsmWay) -> [P2] { way.nodes.filter { nodes[$0] != nil }.map(point) }

    public func wayPolygon(_ way: OsmWay) -> Geometry? {
        let c = wayCoords(way)
        guard c.count >= 4, way.nodes.first == way.nodes.last else { return nil }
        let poly = Geometry.polygon(c)
        return poly.isValid ? poly : poly.buffer(0)
    }

    public func wayLine(_ way: OsmWay) -> Geometry? {
        let c = wayCoords(way)
        return c.count >= 2 ? .lineString(c) : nil
    }

    /// A multipolygon's area: its outer ways joined into rings, less its
    /// inner ones.
    public func relationPolygon(_ relation: OsmRelation) -> Geometry? {
        func rings(_ role: String) -> Geometry? {
            let lines = relation.members.compactMap { m -> Geometry? in
                guard m.type == "way", m.role == role, let w = ways[m.ref] else { return nil }
                return wayLine(w)
            }
            guard !lines.isEmpty else { return nil }
            let merged = Geometry.collection(lines).lineMerge()
            return .unaryUnion(Geometry.polygonize(merged.lines).parts)
        }
        guard let outer = rings("outer"), !outer.isEmpty else { return nil }
        let inner = rings("inner")
        let area = inner.map { $0.isEmpty ? outer : outer.difference($0) } ?? outer
        return area.isValid ? area : area.buffer(0)
    }

    /// Every closed way and multipolygon: (kind, id, tags, shape).
    public func areas() -> [(kind: String, id: Int64, tags: Tags, shape: Geometry)] {
        if let cached = areaCache { return cached }
        var out: [(String, Int64, Tags, Geometry)] = []
        for id in wayOrder {
            let way = ways[id]!
            if !way.tags.isEmpty, way.nodes.first == way.nodes.last, let poly = wayPolygon(way), !poly.isEmpty {
                out.append(("way", id, way.tags, poly))
            }
        }
        for rel in relations where rel.tags["type"] == "multipolygon" {
            if let poly = relationPolygon(rel), !poly.isEmpty { out.append(("relation", rel.id, rel.tags, poly)) }
        }
        areaCache = out
        return out
    }

    private var areaCache: [(kind: String, id: Int64, tags: Tags, shape: Geometry)]?
    private var lineCache: [(id: Int64, tags: Tags, line: Geometry)]?

    /// Every tagged way as a line: (id, tags, line).
    public func lines() -> [(id: Int64, tags: Tags, line: Geometry)] {
        if let cached = lineCache { return cached }
        var out: [(Int64, Tags, Geometry)] = []
        for id in wayOrder {
            let way = ways[id]!
            if !way.tags.isEmpty, let line = wayLine(way) { out.append((id, way.tags, line)) }
        }
        lineCache = out
        return out
    }
}

// MARK: Vectors

public typealias V3 = SIMD3<Double>

public extension SIMD3 where Scalar == Double {
    var length: Double { simd_length(self) }
    var normalized: V3 { let l = simd_length(self); return l > 0 ? self / l : self }
    func dot(_ o: V3) -> Double { simd_dot(self, o) }
    func cross(_ o: V3) -> V3 { simd_cross(self, o) }
}

public extension SIMD2 where Scalar == Double {
    var length: Double { simd_length(self) }
    var normalized: P2 { let l = simd_length(self); return l > 0 ? self / l : self }
    func dot(_ o: P2) -> Double { simd_dot(self, o) }
}

public func v3(_ x: Double, _ y: Double, _ z: Double) -> V3 { V3(x, y, z) }
public func v3(_ p: P2, _ z: Double = 0) -> V3 { V3(p.x, p.y, z) }
