import SwiftUI

/// The one inspector of the window, the same in every view: a header with
/// the view's name, the tiles picked on the map (what every view works on),
/// then the sections of the view chosen at the top. A view adds sections,
/// never a frame of its own.
struct Inspector: View {
    @Environment(Session.self) private var session

    var body: some View {
        let mode = session.workspace.viewMode
        VStack(spacing: 0) {
            PanelHeader(title: mode.rawValue, systemImage: mode.systemImage)
            Form {
                PickedTiles()
                switch mode {
                case .map: MapSections()
                case .roads:
                    if let model = session.model, let roads = session.roads {
                        RoadsSections(model: model, map: roads)
                    } else {
                        Section { Text("No road document: pick tiles that have one on the Map.").foregroundStyle(.secondary) }
                    }
                case .tiles: TilesSections()
                case .light: LightSections()
                case .landmarks: LandmarksSections()
                }
            }
            .formStyle(.grouped)
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

/// The tiles picked on the map, shown at the top of the inspector in every
/// view.
struct PickedTiles: View {
    @Environment(Session.self) private var session

    var body: some View {
        let picked = session.workspace.selection.sorted()
        Section("Tiles picked: \(picked.count)") {
            if picked.isEmpty {
                Text("None: pick tiles on the Map.").foregroundStyle(.secondary)
            } else {
                Text(picked.map(\.name).joined(separator: "  "))
                    .font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(6)
            }
        }
    }
}

extension ViewMode {
    var systemImage: String {
        switch self {
        case .map: "map"
        case .roads: "road.lanes"
        case .tiles: "cube"
        case .light: "sun.max"
        case .landmarks: "building.columns"
        }
    }
}
