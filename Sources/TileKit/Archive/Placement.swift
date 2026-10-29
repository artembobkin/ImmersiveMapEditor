// Copyright (c) 2025-2026 ImmersiveMap contributors.
// SPDX-License-Identifier: MIT

import Foundation

/// `placement.json`, the file next to a model that says where it stands on
/// the map and which building it replaces. The baker bakes every model that
/// has one and ignores a folder without it.
///
///     {
///       "id": "gum",
///       "model": "gum_512.glb",
///       "origin": { "latitude": 55.7546967704, "longitude": 37.6214240342 },
///       "replaces": {
///         "14": ["way/31560418"],
///         "15": ["relation/3330565", "way/246692841", "way/246692843"]
///       },
///       "altitude_m": 0,
///       "cuts_into_ground": false
///     }
///
/// `model` is a path relative to the file. `replaces` lists the features of
/// the map's own tiles the model stands in for, as `node/<id>`, `way/<id>`
/// or `relation/<id>`, under the zoom of the map tiles each list is for. An
/// id names a building only within a zoom: the deepest tiles carry one
/// feature per OSM element (the building's outline and each
/// `building:part`), the tiles above them merge buildings into groups that
/// go by the id of one member. The map hides in a tile exactly the ids
/// listed for that tile's zoom, so a part left out stays standing inside
/// the model. `Scripts/resolve_replaces.py` works the lists out from the
/// map's tiles. The key is empty or absent for a model that replaces
/// nothing. The last two keys are
/// optional. A model that cuts into the ground is kept out of the tile's
/// merged mesh and drawn on its own.
struct Placement: Decodable {
    struct Origin: Decodable {
        let latitude: Double
        let longitude: Double
    }

    let id: String
    let model: String
    let origin: Origin
    let replaces: [String: [String]]?
    let altitudeMeters: Double?
    let cutsIntoGround: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case origin
        case replaces
        case altitudeMeters = "altitude_m"
        case cutsIntoGround = "cuts_into_ground"
    }

    /// The replaced features, the shallowest zoom first.
    func replacedBuildings() throws -> [ReplacedBuilding] {
        let kinds: [Substring: OSMElement.Kind] = ["node": .node, "way": .way, "relation": .relation]
        var lists: [(zoom: Int, names: [String])] = []
        for (key, names) in replaces ?? [:] {
            guard let zoom = Int(key), (0...24).contains(zoom) else {
                throw BakeError("\(self.id): a key of \"replaces\" must be the zoom of the map tiles, not \"\(key)\"")
            }
            lists.append((zoom, names))
        }
        var entries: [ReplacedBuilding] = []
        for (zoom, names) in lists.sorted(by: { $0.zoom < $1.zoom }) {
            var seen = Set<String>()
            for name in names where seen.insert(name).inserted {
                let parts = name.split(separator: "/")
                guard parts.count == 2, let kind = kinds[parts[0]], let id = UInt64(parts[1]),
                      id < 1 << ModelTileFormat.replacedBuildingKindShift else {
                    throw BakeError("\(self.id): an entry of \"replaces\" must be node/<id>, way/<id> or relation/<id>, not \"\(name)\"")
                }
                entries.append(ReplacedBuilding(element: OSMElement(kind: kind, id: id), mapTileZoom: zoom))
            }
        }
        return entries
    }
}

/// The XYZ tile of a coordinate in the Web Mercator grid.
func tileCoordinate(latitude: Double, longitude: Double, zoom: Int) -> (x: Int, y: Int) {
    let side = Double(1 << zoom)
    let x = (longitude + 180) / 360 * side
    let radians = latitude * .pi / 180
    let y = (1 - asinh(tan(radians)) / .pi) / 2 * side
    return (Int(x.rounded(.down)), Int(y.rounded(.down)))
}

/// The west, south, east and north edges of a tile, in degrees.
func tileBounds(zoom: Int, x: Int, y: Int) -> (west: Double, south: Double, east: Double, north: Double) {
    let side = Double(1 << zoom)
    func longitude(_ column: Int) -> Double {
        Double(column) / side * 360 - 180
    }
    func latitude(_ row: Int) -> Double {
        atan(sinh(.pi * (1 - 2 * Double(row) / side))) * 180 / .pi
    }
    return (longitude(x), latitude(y + 1), longitude(x + 1), latitude(y))
}
