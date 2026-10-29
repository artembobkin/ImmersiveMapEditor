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
                Text("The landmark alone as the engine will show it: its palette tones times its light, baked here with the settings below over a white ground, and the engine's sun casting its shadows.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Bake Again", systemImage: "arrow.clockwise") { session.showPreview() }
                    .help("Bakes the landmark's light again with the settings below. Every change below bakes again by itself, a moment after the change; this is for after a model is rebuilt.")
                slider("Lens", $light.lens, 20...90, "%.0f°")
                Text("The camera's lens, its vertical field of view: the engine's is 45°. Narrow, like a telephoto, flattens the building and keeps its walls parallel; wide makes what is near loom and the far shrink. The model keeps its size in the frame.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        Section("Face shade") {
            slider("Reach", $light.faceRadius, 0...30, "%.0f m")
            slider("Step", $light.faceStep, 0...0.2, "%.2f")
            Text("Depth from the building itself, flat over each face: a face shut in by what stands within the reach (a window's reveal and glass, a ceiling under a portico, the wall behind columns, the underside of a cornice) takes its colour a step or more darker, each step this much. 0 m for none.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Creases") {
            slider("Width", $light.creaseRadius, 0...4, "%.1f m")
            slider("Depth", $light.creaseDepth, 0...1, "%.2f")
            Text("A band of shade along every concave edge seen from above, where a roof meets a wall, a chimney or a parapet its roof: how shut in each point is within the width, taking this much of the light where it is shut in whole. Baked into the same light map. 0 m for none.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Light") {
            slider("Strength", $light.depth, 0...1, "%.2f")
            slider("Contrast", $light.gamma, 0.5...3, "%.2f")
            Text("The light gathered over the whole tile, in the same map. Strength: how dark its shade goes, 0 for none (the default: the creases and the face shade alone). Contrast: above 1 deepens the shade near walls and in corners and leaves the open ground alone.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Gathered", selection: $light.mode) {
                Text("Sky light").tag("sky")
                Text("Ambient occlusion").tag("ao")
            }
            if light.mode == "ao" {
                slider("Radius", $light.aoRadius, 1...40, "%.0f m")
                Text("How shut in each surface is within the radius: dark in corners and narrow courtyards, no direction.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                slider("Sky", $light.skyStrength, 0...2, "%.2f")
                Stepper("Bounces: \(light.bounces)", value: $light.bounces, in: 0...6)
                Text("An even sky, a little brighter toward the zenith, its light bouncing between surfaces: no direction.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        Section("Sun") {
            let landmark = workspace.previewSubject != "tile"
            Toggle("Bake a sun", isOn: $light.sun)
            if light.sun {
                slider("From", $light.sunAzimuth, 0...359, "%.0f°")
                slider("Height", $light.sunElevation, 5...90, "%.0f°")
                slider("Strength", $light.sunStrength, 0...3, "%.2f")
                Text("Its shadows are baked: they stay put whatever the engine's sun does.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if landmark {
                Toggle("Engine's sun", isOn: $light.engineSun)
                Text(light.engineSun ? "The engine's shadow, from the bearing and height below (the engine's own sun is from \(Int(Palette.sunFrom))°)."
                                     : "No shadow: the engine adds its own sun.")
                    .font(.callout).foregroundStyle(.secondary)
                if light.engineSun {
                    slider("From", $light.sunAzimuth, 0...359, "%.0f°")
                    slider("Height", $light.sunElevation, 5...90, "%.0f°")
                    slider("Shadow", $light.shadow, 0...1, "%.2f")
                }
                Toggle("Walls toned by the sun", isOn: $light.sided)
                Text("The palette's lit, side and shade tones on every wall and slope by which way it faces against the sun from \(Int(Palette.sunFrom))°. They are the tile's own colours, baked into it, so the engine always shows them: off only to see the colours flat.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("No sun baked: the engine casts the sun's shadows itself, from where its sun is.")
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

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ format: String) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
    }
}
