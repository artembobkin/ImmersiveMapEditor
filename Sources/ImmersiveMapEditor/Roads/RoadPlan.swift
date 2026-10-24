import Foundation
import Geometry
import TileKit

/// The road document as the Roads view edits it: in local metres of its
/// range of tiles, each area's rings together, every marking with all its
/// parameters. The file is TileKit's RoadDocument (its format, reading and
/// writing): a plan is read from it and written back through it, so the
/// editor and the pipeline share one format, byte for byte.
struct RoadPlan {
    struct Tiles { var z, x0, y0, x1, y1: Int }

    struct Area {
        var id: String
        var op: String              // "add" or "cut"
        var rings: [[Vec2]]         // the outer ring first, counter-clockwise, then the holes, clockwise
    }

    struct Marking {
        var id: String
        var kind: String            // line, zebra, zigzag, letter
        var style = "dashed"        // line: solid, dashed, double
        var colour = "white"        // line: white, yellow
        var points: [Vec2] = []     // line, zigzag (its baseline)
        var centre = Vec2.zero      // zebra, letter
        var heading = 0.0           // zebra, letter: degrees counter-clockwise from east
        var span = 10.0             // zebra: kerb to kerb
        var bar = 0.5               // zebra
        var length = 4.0            // zebra: a bar's length
        var side = 1                // zigzag: the roadway on the left (1) or right (-1)
        var step = 2.0              // zigzag
        var depth = 0.9             // zigzag
        var text = "A"              // letter

        /// Where it is, for moving and picking.
        var anchor: Vec2 { points.isEmpty ? centre : points.reduce(.zero, +) / Double(points.count) }
    }

    struct Shelter {
        var id: String
        var position: Vec2
        var heading: Double         // its length along it, the road on its left
    }

    var tiles: Tiles
    var seededDate: String
    var seededRevision: String
    var areas: [Area] = []
    var markings: [Marking] = []
    var shelters: [Shelter] = []

    var projection: Region { Region(z: tiles.z, x0: tiles.x0, y0: tiles.y0, x1: tiles.x1, y1: tiles.y1) }

    var name: String { "\(tiles.z)_\(tiles.x0)_\(tiles.y0)_\(tiles.x1)_\(tiles.y1)" }

    /// A new id for a kind's letter: one more than the highest in use.
    func newID(_ letter: String) -> String {
        let ids = areas.map(\.id) + markings.map(\.id) + shelters.map(\.id)
        let top = ids.filter { $0.hasPrefix(letter) }.compactMap { Int($0.dropFirst(letter.count)) }.max() ?? 0
        return "\(letter)\(top + 1)"
    }

    static func letter(of kind: String) -> String {
        ["line": "m", "zebra": "z", "zigzag": "g", "letter": "l"][kind] ?? "m"
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
        areas = doc.areas.map { Area(id: $0.id, op: $0.op, rings: [$0.outer.map(m)] + $0.holes.map { $0.map(m) }) }
        markings = doc.markings.map { k in
            Marking(id: k.id, kind: k.kind, style: k.style, colour: k.colour, points: k.points.map(m),
                    centre: k.centre.map(m) ?? .zero, heading: k.heading, span: k.span, bar: k.bar, length: k.length,
                    side: k.side, step: k.step, depth: k.depth, text: k.text)
        }
        shelters = doc.shelters.map { Shelter(id: $0.id, position: m($0.position), heading: $0.heading) }
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
        doc.areas = areas.map {
            RoadDocument.Area(id: $0.id, op: $0.op, outer: $0.rings[0].map(ll), holes: $0.rings.dropFirst().map { $0.map(ll) })
        }
        doc.markings = markings.map { k in
            var mark = Mark(kind: k.kind)
            mark.id = k.id
            mark.style = k.style
            mark.colour = k.colour
            mark.points = k.points.map(ll)
            mark.centre = k.kind == "zebra" || k.kind == "letter" ? ll(k.centre) : nil
            mark.heading = k.heading
            mark.span = k.span
            mark.bar = k.bar
            mark.length = k.length
            mark.side = k.side
            mark.step = k.step
            mark.depth = k.depth
            mark.text = k.text
            return mark
        }
        doc.shelters = shelters.map { RoadDocument.Shelter(id: $0.id, position: ll($0.position), heading: $0.heading) }
        return doc
    }
}
