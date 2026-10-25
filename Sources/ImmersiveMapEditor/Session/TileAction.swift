import Foundation

/// What a view builds of the working tile: the one action of its toolbar
/// button, its menu item and the top of its panel, so all three say and do
/// the same.
///
/// - Roads: the road document, seeded from osm2streets and OSM (again, over
///   the hand edits, only when confirmed).
/// - Tiles 3D: the tile built from its sources, its road document and its
///   landmark models, its light left white.
/// - Light: the tile's light baked again, its geometry as built.
enum TileAction {
    case roads, tile, light

    var title: String {
        switch self {
        case .roads: "Seed the Roads"
        case .tile: "Build the Tile"
        case .light: "Bake the Light"
        }
    }

    var systemImage: String {
        switch self {
        case .roads: "road.lanes"
        case .tile: "cube"
        case .light: "sun.max"
        }
    }

    var help: String {
        switch self {
        case .roads:
            "Seed the road document holding the tile from osm2streets and OSM: a new one, or again over the hand edits once confirmed (⌘B)"
        case .tile:
            "Build the tile's model from its OSM, its road document and its landmark models, and export it. The light is not baked: Light bakes it (⌘B)"
        case .light:
            "Bake the tile's light map again with the Light view's settings, its geometry as built (⌘B)"
        }
    }
}

extension ViewMode {
    /// The view's action on the working tile, if it has one.
    var action: TileAction? {
        switch self {
        case .roads: .roads
        case .tiles: .tile
        case .light: .light
        case .landmarks, .buildings: nil
        }
    }
}
