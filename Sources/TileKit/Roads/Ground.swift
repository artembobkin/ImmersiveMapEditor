import Foundation
import Geometry

/// The roads, the only ground a tile has: the engine's vector tile shows
/// the rest under the model. All of it lies flat at `Level.road`, a little
/// above the ground plane so it never fights the vector tile, with no walls:
///
/// - the roadway, asphalt, with its markings cut into it;
/// - a kerb band of grey stone `kerbWidth` wide around the roadway.
///
/// Everything comes from the road document, which the editor corrects by
/// hand. A lab whose tile no document covers seeds one in memory from the
/// tile's own osm2streets output. Nothing is laid under buildings.
public enum Ground {
    /// The road document of the tile: `url`, the one in roads/ that holds the
    /// tile, or, with none, one seeded in memory in the tile's metres.
    public static func document(_ osm: Osm, _ tile: Tile, work: Geometry, paths: WorkspacePaths,
                                url: URL? = nil) throws -> RoadDocument {
        if let url = url ?? RoadDocument.find(z: tile.z, x: tile.x, y: tile.y, in: paths) {
            print("[ground] roads laid from the road document, as it is: \(url.path.components(separatedBy: "/tiles/").last ?? url.lastPathComponent)")
            return try RoadDocument.read(url)
        }
        print("[ground] no road document holds the tile: seeded from its own streets/")
        let content = try Roads.seed(osm, streets: tile.folder.appendingPathComponent("streets"), work: work)
        return Roads.document(content, region: Region(z: tile.z, x0: tile.x, y0: tile.y, x1: tile.x, y1: tile.y))
    }

    /// Lays the roads. Returns the asphalt, the kerb band and the shelters
    /// (local metres, heading in radians).
    public static func build(_ b: Builder, _ osm: Osm, _ tile: Tile, work: Geometry, footprint: Geometry,
                             paths: WorkspacePaths,
                             roads: URL? = nil) throws -> (asphalt: Geometry, kerb: Geometry, shelters: [(P2, Double)]) {
        let shapes = Roads.load(try document(osm, tile, work: work, paths: paths, url: roads), tile, work: work)
        let clean = Roads.clean
        let blocked = clean(footprint)
        let asphalt = clean(shapes.roadway.intersection(work).difference(blocked))
        let kerb = clean(asphalt.buffer(kerbWidth, join: .mitre).intersection(work).difference(asphalt).difference(blocked))
        var white = shapes.white.map { clean($0.intersection(asphalt).simplify(0.02)) }
        let yellow = shapes.yellow.map { clean($0.intersection(asphalt).simplify(0.02)) }
        if let w = white, let y = yellow { white = clean(w.difference(y)) }
        var bare = asphalt
        for p in [white, yellow].compactMap({ $0 }) { bare = clean(bare.difference(p)) }
        for p in bare.polygons { b.fill(p, Level.road, "asphalt", "ground") }
        for p in white?.polygons ?? [] { b.fill(p, Level.road, "marking", "markings") }
        for p in yellow?.polygons ?? [] { b.fill(p, Level.road, "marking_yellow", "markings") }
        for p in kerb.polygons { b.fill(p, Level.road, "kerb", "ground") }
        return (asphalt, kerb, shapes.shelters)
    }

    /// The ground of the construction sites (`landuse=construction`), not
    /// drawn: where their fence goes and their things stand.
    public static func constructionEarth(_ osm: Osm, work: Geometry, footprint: Geometry, asphalt: Geometry,
                                         kerb: Geometry) -> Geometry? {
        let sites = osm.areas().filter { $0.tags["landuse"] == "construction" && $0.shape.intersects(work) }.map(\.shape)
        if sites.isEmpty { return nil }
        let clean = Roads.clean
        return clean(clean(.unaryUnion(sites.map(clean))).intersection(work).difference(clean(footprint))
            .difference(asphalt).difference(kerb).simplify(0.1))
    }
}
