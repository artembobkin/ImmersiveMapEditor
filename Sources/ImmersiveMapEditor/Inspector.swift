import MetalKit
import SwiftUI

/// The window's content: the map and, beside it, the tools, the selection's
/// parameters and the layers.
struct ContentView: View {
    @ObservedObject var model: EditorModel
    let map: MapView
    let tiles: TileView?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if model.viewMode == .tiles, let tiles {
                    MapRepresentable(view: tiles)
                } else {
                    MapRepresentable(view: map)
                }
                Divider()
                VStack(spacing: 0) {
                    Picker("", selection: $model.viewMode) {
                        ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(12)
                    if model.viewMode == .tiles {
                        TilesInspector(model: model, view: tiles)
                    } else {
                        Inspector(model: model, map: map)
                    }
                }
                .frame(width: 270)
            }
            Divider()
            HStack {
                Text(model.viewMode == .tiles ? (model.flying
                    ? "Flight: W A S D, Q down, E up, shift faster, right-drag to look, scroll for speed. Tab to orbit."
                    : "Drag to move, right-drag (or option-drag) to turn and tilt, scroll or pinch to zoom. Tab to fly, F frames, L light map.")
                    : model.tool.hint).lineLimit(1)
                Spacer()
                Text(model.viewMode == .tiles ? model.tileStatus : model.status).lineLimit(1).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }
}

struct MapRepresentable: NSViewRepresentable {
    let view: MTKView
    func makeNSView(context: Context) -> MTKView { view }
    func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.needsDisplay = true
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

/// The 3D view's panel: which tiles, the camera, the light map.
struct TilesInspector: View {
    @ObservedObject var model: EditorModel
    let view: TileView?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tiles").font(.headline)
                    Picker("", selection: $model.tileScope) {
                        ForEach(TileScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if model.tileScope == .one {
                        let t = model.doc.tiles
                        Picker("Tile", selection: Binding(get: { "\(model.tileX)/\(model.tileY)" }, set: { v in
                            let p = v.split(separator: "/").compactMap { Int($0) }
                            if p.count == 2 { model.tileX = p[0]; model.tileY = p[1]; view?.frameTiles() }
                        })) {
                            ForEach(Array(t.y0...t.y1), id: \.self) { y in
                                ForEach(Array(t.x0...t.x1), id: \.self) { x in
                                    Text("\(t.z)/\(x)/\(y)").tag("\(x)/\(y)")
                                }
                            }
                        }
                    }
                    Button("Frame  F") { view?.frameTiles() }
                    Button("Reload the built tiles") { model.tilesRevision += 1 }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("View").font(.headline)
                    Toggle("Fly  Tab", isOn: $model.flying)
                    Toggle("Light map  L", isOn: $model.showLightMap)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Build").font(.headline)
                    Text("Tiles > Build (⌘B) saves the roads and builds every tile of the document. The view reloads them when it is done.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(model.tileStatus).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .onChange(of: model.tileScope) { view?.frameTiles() }
    }
}

struct Inspector: View {
    @ObservedObject var model: EditorModel
    let map: MapView

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
                        Slider(value: $model.cornerRadius, in: 0.5...20)
                        Text("\(model.cornerRadius, specifier: "%.1f") m").monospacedDigit().frame(width: 48)
                    }
                    HStack {
                        Button("Simplify  D") { model.simplifySelection() }
                        Slider(value: $model.tolerance, in: 0.05...2)
                        Text("\(model.tolerance, specifier: "%.2f") m").monospacedDigit().frame(width: 48)
                    }
                    Button("Delete  ⌫") { model.deleteSelection() }
                }
                section("Selection") { SelectionView(model: model) }
                section("Layers") {
                    Toggle("Buildings", isOn: $model.showBuildings)
                    Toggle("OSM centre lines, crossings, stops", isOn: $model.showCentreLines)
                    Toggle("Markings", isOn: $model.showMarkings)
                    Toggle("Point handles  H", isOn: $model.showHandles)
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

/// The parameters of the one selected marking or shelter, editable.
struct SelectionView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let items = model.selection
        if items.isEmpty {
            Text("Nothing selected").foregroundStyle(.secondary)
        } else if items.count == 1, case .marking(let i) = items.first!, i < model.doc.markings.count {
            marking(i)
        } else if items.count == 1, case .shelter(let i) = items.first!, i < model.doc.shelters.count {
            Text("Shelter \(model.doc.shelters[i].id)")
            number("Heading °", { model.doc.shelters[i].heading }) { d, v in d.shelters[i].heading = v }
        } else if items.count == 1, case .area(let i) = items.first!, i < model.doc.areas.count {
            let a = model.doc.areas[i]
            Text("Area \(a.id): \(a.rings.count - 1) holes, \(a.rings.reduce(0) { $0 + $1.count }) points")
            Picker("Op", selection: Binding(get: { a.op }, set: { v in model.change("Edit") { $0.areas[i].op = v } })) {
                Text("Add roadway").tag("add")
                Text("Cut roadway").tag("cut")
            }
        } else {
            let points = items.filter { if case .vertex = $0 { true } else { false } }.count
            Text("\(items.count) selected" + (points > 0 ? ", \(points) points" : ""))
        }
    }

    @ViewBuilder
    func marking(_ i: Int) -> some View {
        let m = model.doc.markings[i]
        Text("\(m.kind.capitalized) \(m.id)")
        switch m.kind {
        case "line":
            Picker("Style", selection: Binding(get: { m.style }, set: { v in model.change("Edit") { $0.markings[i].style = v } })) {
                Text("Solid").tag("solid")
                Text("Dashed").tag("dashed")
                Text("Double").tag("double")
            }
            Picker("Colour", selection: Binding(get: { m.colour }, set: { v in model.change("Edit") { $0.markings[i].colour = v } })) {
                Text("White").tag("white")
                Text("Yellow").tag("yellow")
            }
        case "zebra":
            number("Heading °", { model.doc.markings[i].heading }) { d, v in d.markings[i].heading = v }
            number("Span m", { model.doc.markings[i].span }) { d, v in d.markings[i].span = max(1, v) }
            number("Bar m", { model.doc.markings[i].bar }) { d, v in d.markings[i].bar = max(0.1, v) }
            number("Length m", { model.doc.markings[i].length }) { d, v in d.markings[i].length = max(0.5, v) }
        case "zigzag":
            number("Step m", { model.doc.markings[i].step }) { d, v in d.markings[i].step = max(0.5, v) }
            number("Depth m", { model.doc.markings[i].depth }) { d, v in d.markings[i].depth = v }
            Button("Flip side  X") { model.change("Flip Zigzag") { $0.markings[i].side *= -1 } }
        default:
            number("Heading °", { model.doc.markings[i].heading }) { d, v in d.markings[i].heading = v }
        }
    }

    func number(_ label: String, _ get: @escaping () -> Double, _ set: @escaping (inout RoadDocument, Double) -> Void) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: Binding(get: get, set: { v in model.change("Edit") { set(&$0, v) } }),
                      format: .number.precision(.fractionLength(0...3)))
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }
}
