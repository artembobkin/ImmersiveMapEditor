import Foundation
import TileKit

/// The rules of making landmarks of a tile's buildings, with no window: which
/// of them a kind takes (`LandmarkKind`), what each is named, and each made
/// a landmark whole with the parts standing in it. Make Landmarks… of the
/// Buildings view (`Session.makeLandmarks`) and the area's automation
/// (`AreaMCP`'s prepare_tile) both make them so, one rule for both.
struct LandmarkMaker {
    let paths: WorkspacePaths
    let tile: TileKey
    let projection: Tile
    let buildings: [OsmBuilding]
    /// Whether an OSM building is held by a landmark already, of any tile.
    let held: (String) -> Bool
    /// The named street nearest to a point of the tile, for a name.
    let nearestStreet: (Vec2) -> String?

    /// The buildings `kind` takes that are no landmark yet, their centre
    /// inside the tile, the largest first.
    func candidates(_ kind: LandmarkKind) -> [OsmBuilding] {
        let half = projection.size / 2
        return buildings.filter { b in
            !b.isPart && kind.takes(b) && !held(b.id)
                && (-half...half).contains(b.centroid.x) && (-half...half).contains(b.centroid.y)
        }.sorted { $0.area > $1.area }
    }

    /// The name of a landmark made of `building`: its name, else its
    /// address, else the nearest named street with the building's number
    /// of the tile ("Jalan Veteran 3", the user, 2026-11-04: in Jakarta few
    /// buildings have a name or an address), else "Landmark N".
    func name(for building: OsmBuilding, among existing: [TileLandmark]) -> String {
        if let name = building.name ?? building.address { return name }
        let number = LandmarkCandidates.nextName(among: existing).dropFirst("Landmark ".count)
        if let street = nearestStreet(building.centroid) { return "\(street) \(number)" }
        return "Landmark \(number)"
    }

    /// Each of the `limit` largest buildings `kind` takes made a landmark,
    /// with the parts standing in it that no landmark holds. Returns the
    /// names of those made.
    func make(_ kind: LandmarkKind, limit: Int) -> [String] {
        var made: [String] = []
        var taken = Set<String>()
        for b in candidates(kind).prefix(limit) where !taken.contains(b.id) {
            let parts = buildings.filter { $0.isPart && !held($0.id) && !taken.contains($0.id) && b.contains($0.middle) }
            let name = name(for: b, among: LandmarkCandidates.list(paths, tile: tile))
            guard (try? LandmarkCandidates.make(name: name, buildings: [b] + parts, tile: tile, projection: projection, paths: paths)) != nil
            else { continue }
            taken.formUnion(([b] + parts).map(\.id))
            made.append(name)
        }
        return made
    }
}
