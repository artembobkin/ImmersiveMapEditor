import SwiftUI

/// The Roads view's sections: tools, point operations, the selection,
/// layers, the document.
struct RoadsSections: View {
    @Bindable var model: RoadEditor
    let map: RoadsView

    var body: some View {
        Section("Tool") {
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
        Section("Points") {
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
            Button("Frame the tile  F") { map.frameAll() }
        }
        Section("Document") {
            Text(model.url.lastPathComponent).font(.callout.monospaced())
            Text("\(model.doc.areas.count) areas, \(model.doc.areas.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }) points, \(model.doc.markings.count) markings, \(model.doc.shelters.count) shelters")
                .font(.callout).foregroundStyle(.secondary)
            Text("Seeded \(model.doc.seededDate)").font(.callout).foregroundStyle(.secondary)
        }
    }

    /// A layer's opacity, as a percentage slider.
    func opacity(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: 0...1)
            Text("\(Int((value.wrappedValue * 100).rounded())) %").monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}
