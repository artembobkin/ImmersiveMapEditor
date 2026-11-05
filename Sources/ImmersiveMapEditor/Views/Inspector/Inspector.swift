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
                    if session.choosing == .style { StyleSections() } else { MapSections() }
                } else {
                    if !mode.actions.isEmpty { ActionSection(actions: mode.actions) }
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
                case .preview:
                    LightSections()
                    if session.workspace.previewSubject == "tile" { TilesSections() }
                case .buildings:
                    // A landmark open is all the panel is about: the picked
                    // buildings' sections stayed above it, with Open Landmark
                    // and Model with Claude twice (the user, 2026-11-04).
                    if session.pickedLandmark == nil { BuildingsSections() }
                    LandmarksSections()
                case .style: StyleSections()
                case .engine: EngineSections()
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
                Text(([workspace.fetched.contains(t) ? "OSM fetched" : "not fetched",
                       workspace.built.contains(t) ? "built" : "not built"]
                      + (Features.roads ? [workspace.document(holding: t) != nil ? "has roads" : "no road document"] : [])).joined(separator: ", "))
                    .foregroundStyle(.secondary)
            } else {
                Text("None: pick a tile on the Map.").foregroundStyle(.secondary)
            }
            // The palette, in the panel of every view (the user, 2026-11-05: the
            // toolbar's corner was out of sight): the tile's while one is open,
            // remembered by it, the data folder's while choosing.
            let _ = session.palette.revision
            Picker("Palette", selection: Binding(get: { session.palette.active }, set: { session.palette.select($0) })) {
                ForEach(session.palette.names, id: \.self) { Text($0).tag($0) }
            }
            .help(session.palette.tile == nil
                  ? "The data folder's palette: every tile that remembers none of its own is built and modelled with it. Edited in Style."
                  : "The palette this tile is built and modelled with, remembered by the tile" + (session.palette.remembered ? "" : " once one is picked here (the data folder's \(session.palette.defaultName) until then)") + ". Edited in Style.")
        }
    }
}

/// The view's actions on the working tile, at the top of its sections.
struct ActionSection: View {
    @Environment(Session.self) private var session
    let actions: [TileAction]

    var body: some View {
        Section("Build") {
            ForEach(actions, id: \.title) { action in
                PanelButton(action.title, systemImage: action.systemImage) { session.perform(action) }
                    .disabled(!session.can(action))
                    .help(action.help)
            }
        }
    }
}

/// The build's sheet: what the tile's model holds, each part chosen apart,
/// then Build (the user, 2026-10-30: the choice belongs to the button).
struct BuildSheet: View {
    @Environment(Session.self) private var session

    static let parts: [(key: String, name: String, help: String)] = [
        ("landmarks", "Landmarks", "The models of the tile's landmarks."),
        ("houses", "Typical houses", "The procedure's houses with their windows, from OSM's typical Moscow houses."),
        ("boxes", "Other buildings", "Every other building as a plain box of its outline and height."),
        ("sites", "Construction sites", "The fences, cranes and machines of landuse=construction."),
        ("roads", "Roads", "The roads of the road document with their markings and bus shelters, seeding a document if there is none."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Build \(session.buildTarget?.name ?? "the tile")").font(.headline)
                .help("What the tile's model holds. The light is not baked here: Bake does that after.")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.parts.filter { $0.key != "roads" || Features.roads }, id: \.key) { part in
                    Toggle(part.name, isOn: Binding(get: { session.buildParts.contains(part.key) }, set: { session.toggle(part: part.key, on: $0) }))
                        .toggleStyle(.checkbox)
                        .help(part.help)
                }
            }
            HStack {
                Button("Cancel") { session.buildAsked = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Build", systemImage: "cube") { session.buildTileNow() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.buildParts.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}



extension ViewMode {
    var systemImage: String {
        switch self {
        case .roads: "road.lanes"
        case .preview: "sun.max"
        case .buildings: "building.2"
        case .style: "paintpalette"
        case .engine: "globe"
        }
    }
}
