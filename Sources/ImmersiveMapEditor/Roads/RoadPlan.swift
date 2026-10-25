import Foundation
import Geometry
import TileKit

/// The road document as the Roads view edits it: in local metres of its
/// tile, its objects (RoadObject: roadway areas, markings, bus shelters),
/// each in its group in the file's order. The file is TileKit's
/// RoadDocument (its format, reading and writing): a plan is read from it
/// and written back through it, so the editor and the pipeline share one
/// format, byte for byte.
///
/// A plan holds its objects by reference: `copy` makes one of its own
/// before a change, so the plan an undo step keeps never changes.
struct RoadPlan {
    struct Tiles { var z, x0, y0, x1, y1: Int }

    var tiles: Tiles
    var seededDate: String
    var seededRevision: String
    private(set) var areas: [RoadwayArea] = []
    private(set) var markings: [RoadMarking] = []
    private(set) var shelters: [BusShelter] = []

    /// Every object, in the file's order: areas, markings, shelters.
    var objects: [RoadObject] { areas + markings + shelters }

    var projection: Region { Region(z: tiles.z, x0: tiles.x0, y0: tiles.y0, x1: tiles.x1, y1: tiles.y1) }

    var name: String { "\(tiles.z)_\(tiles.x0)_\(tiles.y0)_\(tiles.x1)_\(tiles.y1)" }

    /// The object of an id, nil when there is none (any more).
    func object(_ id: String) -> RoadObject? { objects.first { $0.id == id } }

    /// A plan of its own: every object copied.
    func copy() -> RoadPlan {
        var c = self
        c.areas = areas.map { $0.copy() as! RoadwayArea }
        c.markings = markings.map { $0.copy() as! RoadMarking }
        c.shelters = shelters.map { $0.copy() as! BusShelter }
        return c
    }

    /// Adds an object at the end of its group, with a new id of its kind.
    /// Returns the id.
    @discardableResult
    mutating func add(_ o: RoadObject) -> String {
        o.id = newID(type(of: o).idLetter)
        switch o {
        case let a as RoadwayArea: areas.append(a)
        case let m as RoadMarking: markings.append(m)
        case let s as BusShelter: shelters.append(s)
        default: break
        }
        return o.id
    }

    /// Takes the objects of the ids out.
    mutating func remove(_ ids: Set<String>) {
        areas.removeAll { ids.contains($0.id) }
        markings.removeAll { ids.contains($0.id) }
        shelters.removeAll { ids.contains($0.id) }
    }

    /// A new id for a kind's letter: one more than the highest in use.
    func newID(_ letter: String) -> String {
        let top = objects.map(\.id).filter { $0.hasPrefix(letter) }.compactMap { Int($0.dropFirst(letter.count)) }.max() ?? 0
        return "\(letter)\(top + 1)"
    }
}

// MARK: To and from the file

extension RoadPlan {
    static func read(_ url: URL) throws -> RoadPlan { RoadPlan(try RoadDocument.read(url)) }

    func write(_ url: URL) throws { try document.write(url) }

    init(_ doc: RoadDocument) {
        tiles = Tiles(z: doc.z, x0: doc.x0, y0: doc.y0, x1: doc.x1, y1: doc.y1)
        seededDate = doc.seededDate
        seededRevision = doc.seededRevision
        let proj = Region(z: doc.z, x0: doc.x0, y0: doc.y0, x1: doc.x1, y1: doc.y1)
        func m(_ p: P2) -> Vec2 { proj.metres(lat: p.y, lon: p.x) }
        areas = doc.areas.map { RoadwayArea(id: $0.id, op: $0.op, rings: [$0.outer.map(m)] + $0.holes.map { $0.map(m) }) }
        markings = doc.markings.map { RoadMarking.make($0, m) }
        shelters = doc.shelters.map { BusShelter(id: $0.id, position: m($0.position), heading: $0.heading) }
    }

    /// The plan as the file has it, in longitude and latitude.
    var document: RoadDocument {
        let proj = projection
        func ll(_ p: Vec2) -> P2 {
            let (lon, lat) = proj.lonLat(p)
            return P2(lon, lat)
        }
        var doc = RoadDocument(z: tiles.z, x0: tiles.x0, y0: tiles.y0, x1: tiles.x1, y1: tiles.y1,
                               seededDate: seededDate, seededRevision: seededRevision)
        for o in objects { o.export(into: &doc, ll) }
        return doc
    }
}
