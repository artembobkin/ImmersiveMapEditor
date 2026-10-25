import Foundation
import Geometry

/// Brings a workspace of the older layout (a TilePipeline folder: data/,
/// roads/, out/tiles/) into the one-folder-a-tile layout of `WorkspacePaths`,
/// copying: the old folder is only read.
///
/// - data/<z>_<x>_<y>/ becomes the tile's osm/, out/tiles/<z>/<x>/<y>/ its
///   build/.
/// - A road document of a range is cut into one document a tile, hand edits
///   kept: the areas cut to the tile and the margin a seed of the tile would
///   reach (`Seed.margin`), so a tile's roadway runs on under its edge as
///   before; a marking goes to every tile whose margin it touches, a shelter
///   to every one whose margin holds it. What the range was seeded from becomes each tile's roads/seed/.
/// - landmarks/ and config/ are copied whole.
///
/// What the new workspace has already is kept, never written over.
public enum Migration {
    public static func run(from old: URL, to paths: WorkspacePaths) throws {
        let fm = FileManager.default
        func copy(_ from: URL, _ to: URL) throws {
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return }
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: from, to: to)
        }
        try copy(old.appendingPathComponent("landmarks"), paths.landmarks)
        try copy(old.appendingPathComponent("config"), paths.config)

        // The tiles' sources.
        let data = old.appendingPathComponent("data")
        for name in ((try? fm.contentsOfDirectory(atPath: data.path)) ?? []).sorted() {
            let n = name.split(separator: "_").compactMap { Int($0) }
            guard n.count == 3 else { continue }
            try copy(data.appendingPathComponent(name), paths.tileData(z: n[0], x: n[1], y: n[2]))
            print("[migrate] \(n[0])/\(n[1])/\(n[2]) osm")
        }
        // The built tiles.
        let out = old.appendingPathComponent("out/tiles")
        for z in (try? fm.contentsOfDirectory(atPath: out.path)) ?? [] {
            for x in (try? fm.contentsOfDirectory(atPath: out.appendingPathComponent(z).path)) ?? [] {
                for y in (try? fm.contentsOfDirectory(atPath: out.appendingPathComponent("\(z)/\(x)").path)) ?? [] {
                    guard let zi = Int(z), let xi = Int(x), let yi = Int(y) else { continue }
                    try copy(out.appendingPathComponent("\(z)/\(x)/\(y)"), paths.tileOut(z: zi, x: xi, y: yi))
                    print("[migrate] \(z)/\(x)/\(y) build")
                }
            }
        }
        // The road documents, a tile each.
        let roads = old.appendingPathComponent("roads")
        for name in ((try? fm.contentsOfDirectory(atPath: roads.path)) ?? []).sorted() where name.hasSuffix(".json") {
            let doc = try RoadDocument.read(roads.appendingPathComponent(name))
            let seeded = data.appendingPathComponent("regions/\(doc.name)")
            for y in doc.y0...doc.y1 {
                for x in doc.x0...doc.x1 {
                    let url = paths.roadDocument(z: doc.z, x: x, y: y)
                    guard !fm.fileExists(atPath: url.path) else { continue }
                    let part = cut(doc, x: x, y: y)
                    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try part.write(url)
                    try copy(seeded, paths.seed(z: doc.z, x: x, y: y))
                    print("[migrate] \(doc.z)/\(x)/\(y) roads from \(name): \(part.areas.count) areas, "
                          + "\(part.markings.count) markings, \(part.shelters.count) shelters")
                }
            }
        }
    }

    /// One tile's part of a range's road document.
    static func cut(_ doc: RoadDocument, x: Int, y: Int) -> RoadDocument {
        let region = Region(z: doc.z, x0: x, y0: y, x1: x, y1: y)
        let reach = region.bounds.buffer(Seed.margin, join: .mitre)
        func metres(_ p: P2) -> P2 { region.metres(lat: p.y, lon: p.x) }
        func degrees(_ p: P2) -> P2 {
            let (lon, lat) = region.lonLat(p)
            return P2(lon, lat)
        }
        func open(_ ring: [P2]) -> [P2] { ring.count > 1 && ring.first == ring.last ? Array(ring.dropLast()) : ring }
        let (x0, y0, x1, y1) = reach.bounds
        func inside(_ p: P2) -> Bool { let m = metres(p); return m.x >= x0 && m.x <= x1 && m.y >= y0 && m.y <= y1 }

        var part = RoadDocument(z: doc.z, x0: x, y0: y, x1: x, y1: y, seededDate: doc.seededDate, seededRevision: doc.seededRevision)
        for a in doc.areas {
            let shape = Geometry.polygon(a.outer.map(metres), holes: a.holes.map { $0.map(metres) }).intersection(reach)
            for (k, p) in shape.polygons.enumerated() where p.area > 0.01 {
                let o = p.oriented()
                part.areas.append(RoadDocument.Area(id: k == 0 ? a.id : "\(a.id)-\(k)", op: a.op,
                                                    outer: open(o.exterior).map(degrees),
                                                    holes: o.interiors.map { open($0).map(degrees) }))
            }
        }
        part.markings = doc.markings.filter { m in
            if let c = m.centre { return inside(c) }
            // A line by its course, not its points: a long one crosses the
            // margin with its points beyond it.
            return m.points.count > 1 ? Geometry.lineString(m.points.map(metres)).intersects(reach) : m.points.contains(where: inside)
        }
        part.shelters = doc.shelters.filter { inside($0.position) }
        return part
    }
}
