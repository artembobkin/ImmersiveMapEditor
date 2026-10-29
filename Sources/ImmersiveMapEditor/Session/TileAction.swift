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
        case .light: "Bake"
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
            "Build the tile's model: its buildings and landmarks from OSM, its roads laid from the road document as it is (never seeded again: that is Roads'), and export it. The light is not baked: Light bakes it (⌘B)"
        case .light:
            "Bake the tile's light and the faces' shade into its textures with the modifiers below, its geometry as built (⌘B)"
        }
    }
}

extension ViewMode {
    /// The view's actions on the working tile, if it has any: Preview
    /// builds the tile and bakes its light (the user, 2026-10-29: one view
    /// of the tile in 3D, Tiles 3D and Preview made one).
    var actions: [TileAction] {
        switch self {
        case .roads: [.roads]
        case .preview: [.tile, .light]
        case .buildings, .style: []
        }
    }
}
