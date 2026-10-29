import SwiftUI
import TileKit

/// The Preview's sections: what is shown lit (the tile, or one of its
/// landmarks alone), how, what light is baked (the sky with its bounces or
/// ambient occlusion, a sun or none), the light map's density, and the
/// tile's light map as it is. Bake the Light, at the top of the panel,
/// bakes the tile's with these, the geometry as built (`pipeline bake`); a
/// landmark's is baked here as soon as a setting changes.
struct LightSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var light = session.lightSettings
        @Bindable var workspace = session.workspace
        Section("Show") {
            Picker("Subject", selection: $workspace.previewSubject) {
                Text("The tile").tag("tile")
                ForEach(session.candidates.filter { $0.model != nil }) { Text($0.name).tag($0.id) }
            }
            if workspace.previewSubject == "tile" {
                Picker("Shading", selection: $workspace.lightShading) {
                    ForEach([TileShading.lit, .light]) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } else {
                Text("The landmark alone as the engine will show it: its colours and its light from the modifiers below, baked here over a white ground.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Bake Again", systemImage: "arrow.clockwise") { session.showPreview() }
                    .help("Bakes the landmark's light again with the settings below. Every change below bakes again by itself, a moment after the change; this is for after a model is rebuilt.")
                slider("Lens", $light.lens, 20...90, "%.0f°")
                Text("The camera's lens, its vertical field of view: the engine's is 45°. Narrow, like a telephoto, flattens the building and keeps its walls parallel; wide makes what is near loom and the far shrink. The model keeps its size in the frame.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        Section("Modifiers") {
            Text("The light as a stack of modifiers, each on or off with its own settings, shown here and baked into the tile: some into its light map, some into the colours of its faces.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(light.modifiers.indices, id: \.self) { i in
                let m = light.modifiers[i]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle(Lighting.Modifier.name(of: m.kind), isOn: $light.modifiers[i].on)
                        Button { light.remove(at: i) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Remove this modifier from the stack.")
                    }
                    if m.on { controls(i, m.kind) }
                }
            }
            Menu("Add a modifier") {
                ForEach(Lighting.Modifier.kinds, id: \.kind) { k in
                    Button(k.name) { light.add(k.kind) }.disabled(!light.canAdd(k.kind))
                }
            }
        }
        Section("Engine's sun") {
            let landmark = workspace.previewSubject != "tile"
            if landmark {
                Toggle("Shadow", isOn: $light.engineSun)
                Text(light.engineSun ? "The engine's shadow of the sun, from the bearing and height below (the engine's own sun is from \(Int(Palette.sunFrom))°); not baked."
                                     : "No shadow shown: the engine adds its own sun.")
                    .font(.callout).foregroundStyle(.secondary)
                if light.engineSun {
                    slider("From", $light.sunAzimuth, 0...359, "%.0f°")
                    slider("Height", $light.sunElevation, 5...90, "%.0f°")
                    slider("Depth", $light.shadow, 0...1, "%.2f")
                }
            } else {
                Text("The engine casts the sun's shadows itself, from where its sun is.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        Section("Quality") {
            Picker("Light map", selection: $light.size) {
                ForEach([512, 1024, 2048], id: \.self) { Text("\($0) px a tile").tag($0) }
            }
            Picker("Samples", selection: $light.samples) {
                ForEach([64, 128, 256, 512, 1024], id: \.self) { Text("\($0)").tag($0) }
            }
        }
        Section("Light map") {
            if let t = workspace.tile, let map = session.lights.maps[t] {
                Text(map.baked ? "\(map.px) px, overhang \(map.overhang, specifier: "%.0f") m" : "Not baked yet: white.")
                    .foregroundStyle(.secondary)
            } else {
                Text("None: the tile is not built.").foregroundStyle(.secondary)
            }
        }
        .task(id: "\(workspace.tile?.name ?? "") \(workspace.tilesRevision)") {
            if let t = workspace.tile { session.lights.load([t], from: workspace) }
        }
    }

    /// A modifier's parameter as a binding into the stack.
    private func param(_ i: Int, _ key: String) -> Binding<Double> {
        let light = session.lightSettings
        return Binding(get: { light.modifiers.indices.contains(i) ? light.modifiers[i][key] : 0 },
                       set: { if light.modifiers.indices.contains(i) { light.modifiers[i][key] = $0 } })
    }

    /// Each kind's controls and what it does.
    @ViewBuilder private func controls(_ i: Int, _ kind: String) -> some View {
        switch kind {
        case "faceShade":
            slider("Reach", param(i, "reach"), 0...30, "%.0f m")
            slider("Step", param(i, "step"), 0...0.2, "%.2f")
            note("Depth from the building itself, flat over each face: a face shut in by what stands within the reach (a window's reveal and glass, a ceiling under a portico, the wall behind columns, the underside of a cornice) takes its colour a step or more darker, each step this much.")
        case "creases":
            slider("Width", param(i, "width"), 0...4, "%.1f m")
            slider("Depth", param(i, "depth"), 0...1, "%.2f")
            note("A band of shade along every concave edge seen from above, where a roof meets a wall, a chimney or a parapet its roof, in the light map: how shut in each point is within the width, taking this much of the light where shut in whole.")
        case "sides":
            note("The palette's lit, side and shade tones on every wall and slope by which way it faces against the sun from \(Int(Palette.sunFrom))°: the engine's sun must come from there too.")
        case "lambert":
            slider("From", param(i, "from"), 0...359, "%.0f°")
            slider("Height", param(i, "height"), 5...90, "%.0f°")
            slider("Strength", param(i, "strength"), 0...1, "%.2f")
            note("A lamp from a direction, baked into the colours flat over each face: a face turned from it loses this much of its light, one facing it none. The Landmarks view's lamp, in the tile.")
        case "sky":
            slider("Strength", param(i, "strength"), 0...1, "%.2f")
            slider("Contrast", param(i, "contrast"), 0.5...3, "%.2f")
            slider("Sky", param(i, "sky"), 0...2, "%.2f")
            Stepper("Bounces: \(Int(session.lightSettings.modifiers[i]["bounces"]))", value: param(i, "bounces"), in: 0...6, step: 1)
            note("An even sky, a little brighter toward the zenith, its light bouncing between surfaces, in the light map: open ground lit, courtyards and the feet of walls in shade. Strength: how dark the shade goes. Contrast: above 1 deepens it near walls and leaves the open ground alone.")
        case "ao":
            slider("Radius", param(i, "radius"), 1...40, "%.0f m")
            slider("Depth", param(i, "depth"), 0...1, "%.2f")
            note("How shut in each point is within the radius, in the light map: dark in corners and narrow courtyards, no direction, taking this much of the light where shut in whole.")
        case "sun":
            slider("From", param(i, "from"), 0...359, "%.0f°")
            slider("Height", param(i, "height"), 5...90, "%.0f°")
            slider("Strength", param(i, "strength"), 0...3, "%.2f")
            note("A sun baked into the light map with its shadows: they stay put whatever the engine's sun does. Off by default, since the engine casts the sun's shadows itself.")
        default:
            EmptyView()
        }
    }

    private func note(_ text: String) -> some View { Text(text).font(.callout).foregroundStyle(.secondary) }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ format: String) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
    }
}
