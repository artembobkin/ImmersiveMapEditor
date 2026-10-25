import SwiftUI

/// The Roads view's panel: tools, point operations, the selection, layers.
struct RoadsPanel: View {
    @Bindable var model: RoadEditor
    let map: RoadsView

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Tool") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(Tool.allCases) { tool in
                            Button { model.tool = tool } label: {
                                HStack {
                                    Text(tool.rawValue)
                                    Spacer()
                                    Text(tool.key).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(model.tool == tool ? .accentColor : nil)
                        }
                    }
                }
                section("Points") {
                    HStack {
                        Button("Straighten  S") { model.straighten() }
                        Button("Align  ⇧S") { model.straighten(keep: true) }
                    }
                    HStack {
                        Button("Round  R") { model.roundCorners() }
                        Slider(value: $model.settings.cornerRadius, in: 0.5...20)
                        Text("\(model.settings.cornerRadius, specifier: "%.1f") m").monospacedDigit().frame(width: 48)
                    }
                    HStack {
                        Button("Simplify  D") { model.simplifySelection() }
                        Slider(value: $model.settings.tolerance, in: 0.05...2)
                        Text("\(model.settings.tolerance, specifier: "%.2f") m").monospacedDigit().frame(width: 48)
                    }
                    Button("Delete  ⌫") { model.deleteSelection() }
                }
                section("Selection") { SelectionPanel(model: model) }
                section("Layers") {
                    Toggle("Buildings", isOn: $model.layers.buildings)
                    Toggle("OSM centre lines, crossings, stops", isOn: $model.layers.centreLines)
                    Toggle("Markings", isOn: $model.layers.markings)
                    Toggle("Satellite (Mapbox)  I", isOn: $model.layers.satellite)
                    if model.layers.satellite { MapboxToken(map: map) }
                    Toggle("Point handles  H", isOn: $model.layers.handles)
                    Button("Frame the tiles  F") { map.frameAll() }
                }
                section("Document") {
                    Text(model.url.lastPathComponent).font(.callout.monospaced())
                    Text("\(model.doc.areas.count) areas, \(model.doc.areas.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }) points, \(model.doc.markings.count) markings, \(model.doc.shelters.count) shelters")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Seeded \(model.doc.seededDate)").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// The Mapbox token the satellite imagery is fetched with, kept in the
/// user's defaults. A public token (pk.) of a free Mapbox account will do.
struct MapboxToken: View {
    let map: RoadsView
    @AppStorage(SatelliteTiles.tokenKey) private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureField("Mapbox token", text: $token)
                .textFieldStyle(.roundedBorder)
                .onSubmit { map.satelliteTokenChanged() }
            if token.isEmpty {
                Link("Get a token at mapbox.com", destination: URL(string: "https://account.mapbox.com/access-tokens/")!)
                    .font(.callout)
            }
        }
        .onChange(of: token) { map.satelliteTokenChanged() }
    }
}
