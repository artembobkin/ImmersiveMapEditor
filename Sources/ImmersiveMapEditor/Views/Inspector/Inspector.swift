import SwiftUI

/// The one inspector of the window, the same in every view: a header with
/// the view's name, the working tile (picked on the map, the one every view
/// works on), then the sections of the view chosen at the top. A view adds sections,
/// never a frame of its own.
struct Inspector: View {
    @Environment(Session.self) private var session

    var body: some View {
        let mode = session.workspace.viewMode
        let working = session.phase == .working
        VStack(spacing: 0) {
            if working {
                PanelHeader(title: mode.rawValue, systemImage: mode.systemImage)
            } else {
                PanelHeader(title: "Choose a Tile", systemImage: "map")
            }
            Form {
                WorkingTile()
                if !working {
                    MapSections()
                } else {
                    if let action = mode.action { ActionSection(action: action) }
                    modeSections(mode)
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder private func modeSections(_ mode: ViewMode) -> some View {
                switch mode {
                case .roads:
                    if let model = session.model, let roads = session.roads {
                        RoadsSections(model: model, map: roads)
                    } else {
                        Section { Text("No road document holds the tile.").foregroundStyle(.secondary) }
                    }
                case .tiles: TilesSections()
                case .preview: LightSections()
                case .landmarks: LandmarksSections()
                case .buildings: BuildingsSections()
                case .style: StyleSections()
                }
    }
}

/// The header of a panel, the inspector's and the bottom one's alike.
struct PanelHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage).font(.headline)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            Divider()
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, systemImage: String) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

/// The tile shown (open, or picked while choosing), at the top of the
/// inspector: its name and what the workspace has of it.
struct WorkingTile: View {
    @Environment(Session.self) private var session

    var body: some View {
        let workspace = session.workspace
        Section("Tile") {
            if let t = session.shownTile {
                Text(verbatim: t.name).font(.body.monospaced())
                Text([workspace.fetched.contains(t) ? "OSM fetched" : "not fetched",
                      workspace.built.contains(t) ? "built" : "not built",
                      workspace.document(holding: t) != nil ? "has roads" : "no road document"].joined(separator: ", "))
                    .foregroundStyle(.secondary)
            } else {
                Text("None: pick a tile on the Map.").foregroundStyle(.secondary)
            }
        }
    }
}

/// The view's action on the working tile, at the top of its sections, as
/// the toolbar's button does it.
struct ActionSection: View {
    @Environment(Session.self) private var session
    let action: TileAction

    var body: some View {
        Section("Build") {
            Button(action.title, systemImage: action.systemImage) { session.perform(action) }
                .disabled(!session.can(action))
            Text(action.help).font(.callout).foregroundStyle(.secondary)
        }
    }
}

extension ViewMode {
    var systemImage: String {
        switch self {
        case .roads: "road.lanes"
        case .tiles: "cube"
        case .preview: "sun.max"
        case .landmarks: "building.columns"
        case .buildings: "building.2"
        case .style: "paintpalette"
        }
    }
}
