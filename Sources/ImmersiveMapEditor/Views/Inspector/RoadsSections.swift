import SwiftUI

/// The Roads view's sections: tools, point operations, the selection,
/// layers, the document.
struct RoadsSections: View {
    @Bindable var model: RoadEditor
    let map: RoadsView

    private let pair = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        Section("Tool") {
            LazyVGrid(columns: pair, spacing: 6) {
                ForEach(Tool.allCases) { tool in
                    PanelButton(tool.rawValue, key: tool.key) { model.tool = tool }
                        .tint(model.tool == tool ? .accentColor : nil)
                }
            }
        }
        Section("Points") {
            LazyVGrid(columns: pair, spacing: 6) {
                PanelButton("Straighten", key: "S") { model.straighten() }
                PanelButton("Align", key: "⇧S") { model.straighten(keep: true) }
                PanelButton("Round", key: "R") { model.roundCorners() }
                PanelButton("Simplify", key: "D") { model.simplifySelection() }
            }
            metres("Round radius", $model.settings.cornerRadius, 0.5...20, "%.1f")
            metres("Simplify tolerance", $model.settings.tolerance, 0.05...2, "%.2f")
            PanelButton("Delete", key: "⌫") { model.deleteSelection() }
        }
        Section("Selection") { SelectionSections(model: model) }
        Section("Layers") {
            Toggle("Buildings", isOn: $model.layers.buildings)
            Toggle("OSM centre lines, crossings, stops", isOn: $model.layers.centreLines)
            Toggle("Markings", isOn: $model.layers.markings)
            Toggle("Satellite  I", isOn: $model.layers.satellite)
            if model.layers.satellite {
                Picker("Source", selection: $model.layers.imagery) {
                    ForEach(ImagerySource.allCases) { Text($0.name).tag($0) }
                }
                if model.layers.imagery.needsKey && model.layers.imagery.key.isEmpty {
                    Text("\(model.layers.imagery.name) needs a key: Settings (⌘,).").font(.callout).foregroundStyle(.secondary)
                }
                opacity("Satellite", $model.layers.satelliteOpacity)
                opacity("Roadway", $model.layers.roadwayOpacity)
            }
            Toggle("Point handles  H", isOn: $model.layers.handles)
            PanelButton("Frame the tile", key: "F") { map.frameAll() }
        }
        Section("Document") {
            Text(model.url.lastPathComponent).font(.callout.monospaced())
            Text("\(model.doc.areas.count) areas, \(model.doc.areas.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }) points, \(model.doc.markings.count) markings, \(model.doc.shelters.count) shelters")
                .font(.callout).foregroundStyle(.secondary)
            Text("Seeded \(model.doc.seededDate)").font(.callout).foregroundStyle(.secondary)
        }
    }

    /// A length in metres, as a slider with its value.
    private func metres(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ format: String) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: range)
            Text(String(format: format + " m", value.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
    }

    /// A layer's opacity, as a percentage slider.
    private func opacity(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: 0...1)
            Text("\(Int((value.wrappedValue * 100).rounded())) %").monospacedDigit().frame(width: 52, alignment: .trailing)
        }
    }
}
