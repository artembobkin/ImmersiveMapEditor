import Foundation

/// What a view builds of the working tile: the one action of its toolbar
/// button, its menu item and the top of its panel, so all three say and do
/// the same.
///
/// - Roads: the road document, seeded from osm2streets and OSM (again, over
///   the hand edits, only when confirmed).
/// - Preview: the tile built from its sources, its road document and its
///   landmark models.
enum TileAction {
    case roads, tile
    /// Engine, and Preview beside its build: every built tile whose inputs
    /// changed built again, the tile open too when it has never been, then
    /// all into the model archive the Engine view reads (the user,
    /// 2026-11-21: from the Preview, a way to see the models in the engine).
    case engine

    var title: String {
        switch self {
        case .roads: "Seed the Roads"
        case .tile: "Build the Tile…"
        case .engine: "Update the Archive"
        }
    }

    var systemImage: String {
        switch self {
        case .roads: "road.lanes"
        case .tile: "cube"
        case .engine: "shippingbox"
        }
    }

    var help: String {
        switch self {
        case .roads:
            "Seed the road document holding the tile from osm2streets and OSM: a new one, or again over the hand edits once confirmed (⌘B)"
        case .tile:
            "The tile's model from OSM and the road document, the parts you choose, exported (⌘B)"
        case .engine:
            "Every built tile whose OSM, landmarks or palette changed is built again, the tile open too if it never was, then all go into the engine's model archive in the data folder (engine/), which the Engine view reads"
        }
    }
}

extension ViewMode {
    /// The view's actions on the working tile, if it has any, the first on
    /// ⌘B: Preview builds the tile and updates the archive (the user, 2026-10-29: one view of the tile in 3D,
    /// Tiles 3D and Preview made one).
    var actions: [TileAction] {
        switch self {
        case .roads: [.roads]
        case .preview: [.tile, .engine]
        case .engine: [.engine]
        case .buildings, .style: []
        }
    }
}
