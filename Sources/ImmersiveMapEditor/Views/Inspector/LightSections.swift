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
    /// Whether the lighting is in the panel: the shading, the modifiers,
    /// the engine's sun, the quality and the light map, and Bake among the
    /// tile's actions. Off for the first version (the user, 2026-11-05: the
    /// tiles exported and archived, the light left for later); the build
    /// still bakes the tile's light with the standard settings.
    static let lightingShown = Features.lighting

    var body: some View {
        @Bindable var light = session.lightSettings
        @Bindable var workspace = session.workspace
        Section("Show") {
            Picker("Subject", selection: $workspace.previewSubject) {
                Text("The tile").tag("tile")
                Text("All the landmarks").tag("landmarks")
                ForEach(session.candidates.filter { $0.model != nil }) { Text($0.name).tag($0.id) }
            }
            .help("The tile as the engine shows it; all the landmarks' models together where the build places them, their palette alone, with no build; or one landmark alone, its colours and its light from the modifiers below, baked here over a white ground.")
            PanelButton("Rebuild Landmarks from Recipes", systemImage: "hammer") { session.rebuildLandmarks() }
                .disabled(session.landmarksWithRecipes == 0 || session.workspace.tile.map { session.jobs.isActive(.tile($0)) } ?? true)
                .help("Every landmark of the tile with a recipe built again from it (\(session.landmarksWithRecipes) of them): after a change of the palette, or of a recipe by hand. The tile itself is not built: see them together as All the landmarks.")
            if workspace.previewSubject == "tile" {
                if Self.lightingShown {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shading")
                    Picker("Shading", selection: $workspace.lightShading) {
                        ForEach([TileShading.lit, .light]) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                }
            } else {
                slider("Lens", $light.lens, 20...90, "%.0f°")
                    .help("The camera's lens, its vertical field of view: the engine's is 45°. Narrow, like a telephoto, flattens the building and keeps its walls parallel; wide makes what is near loom and the far shrink. The model keeps its size in the frame.")
            }
        }
        if Self.lightingShown {
        Section("Modifiers") {
            ForEach(light.modifiers.indices, id: \.self) { i in
                let m = light.modifiers[i]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle(Lighting.Modifier.name(of: m.kind), isOn: $light.modifiers[i].on)
                            .help(description(m.kind))
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
            .help("The light as a stack of modifiers, each on or off with its own settings, shown here and baked into the tile: some into its light map, some into the colours of its faces.")
        }
        if !["tile", "landmarks"].contains(workspace.previewSubject) {
            Section("Engine's sun") {
                Toggle("Shadow", isOn: $light.engineSun)
                    .help("The engine's shadow of the sun on the landmark, from the bearing and height below (the engine's own sun is from \(Int(Palette.sunFrom))°); not baked. Off: the engine adds its own sun.")
                if light.engineSun {
                    SunPad(from: $light.sunAzimuth, height: $light.sunElevation)
                    slider("Depth", $light.shadow, 0...1, "%.2f")
                        .help("How dark where a surface is fully in the shadow, with the engine's cool tint.")
                }
            }
        }
        Section("Quality") {
            Picker("Light map", selection: $light.size) {
                ForEach([512, 1024, 2048], id: \.self) { Text("\($0) px").tag($0) }
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
        }
        Section {}
        .task(id: "\(workspace.tile?.name ?? "") \(workspace.tilesRevision)") {
            if let t = workspace.tile { session.lights.load([t], from: workspace) }
        }
        .onChange(of: light.previewKey) { session.lightSettingsChanged() }
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
        case "creases":
            slider("Width", param(i, "width"), 0...4, "%.1f m")
            slider("Depth", param(i, "depth"), 0...1, "%.2f")
        case "sides":
            EmptyView()
        case "lambert":
            SunPad(from: param(i, "from"), height: param(i, "height"))
            slider("Strength", param(i, "strength"), 0...1, "%.2f")
        case "sky":
            slider("Strength", param(i, "strength"), 0...1, "%.2f")
            slider("Contrast", param(i, "contrast"), 0.5...3, "%.2f")
            slider("Sky", param(i, "sky"), 0...2, "%.2f")
            Stepper("Bounces: \(Int(session.lightSettings.modifiers[i]["bounces"]))", value: param(i, "bounces"), in: 0...6, step: 1)
        case "ao":
            slider("Radius", param(i, "radius"), 1...40, "%.0f m")
            slider("Depth", param(i, "depth"), 0...1, "%.2f")
        case "sun":
            SunPad(from: param(i, "from"), height: param(i, "height"))
            slider("Strength", param(i, "strength"), 0...3, "%.2f")
        default:
            EmptyView()
        }
    }

    /// What each kind does, on its row's tooltip.
    private func description(_ kind: String) -> String {
        switch kind {
        case "faceShade": return "Depth from the building itself, flat over each face: a face shut in by what stands within the reach (a window's reveal and glass, a ceiling under a portico, the wall behind columns, the underside of a cornice) takes its colour a step or more darker, each step this much."
        case "creases": return "A band of shade along every concave edge seen from above, where a roof meets a wall, a chimney or a parapet its roof, in the light map: how shut in each point is within the width, taking this much of the light where shut in whole."
        case "sides": return "The palette's lit, side and shade tones on every wall and slope by which way it faces against the sun from \(Int(Palette.sunFrom))°: the engine's sun must come from there too."
        case "lambert": return "A lamp from a direction, baked into the colours flat over each face: a face turned from it loses this much of its light, one facing it none."
        case "sky": return "An even sky, a little brighter toward the zenith, its light bouncing between surfaces, in the light map: open ground lit, courtyards and the feet of walls in shade. Strength: how dark the shade goes. Contrast: above 1 deepens it near walls and leaves the open ground alone."
        case "ao": return "How shut in each point is within the radius, in the light map: dark in corners and narrow courtyards, no direction, taking this much of the light where shut in whole."
        case "sun": return "A sun baked into the light map with its shadows: they stay put whatever the engine's sun does. Off by default, since the engine casts the sun's shadows itself."
        default: return ""
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

/// Where a light comes from, on a square: the scene from above, north up,
/// the building at the cross in the middle. The sun is dragged about it:
/// its bearing is the direction from the middle, its height how near the
/// middle it stands (overhead at the cross, on the horizon at the ring).
/// Fixed to the scene, not the camera (the user, 2026-10-29).
struct SunPad: View {
    @Binding var from: Double
    @Binding var height: Double
    private let side = 150.0

    var body: some View {
        let r = side / 2 - 10
        let d = r * (1 - (min(max(height, 5), 90) - 5) / 85)
        let a = from * .pi / 180
        let sun = CGPoint(x: side / 2 + d * sin(a), y: side / 2 - d * cos(a))
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor))
                Circle().stroke(.secondary.opacity(0.5), lineWidth: 1).frame(width: 2 * r, height: 2 * r)
                Path { p in
                    p.move(to: CGPoint(x: side / 2 - 8, y: side / 2)); p.addLine(to: CGPoint(x: side / 2 + 8, y: side / 2))
                    p.move(to: CGPoint(x: side / 2, y: side / 2 - 8)); p.addLine(to: CGPoint(x: side / 2, y: side / 2 + 8))
                }
                .stroke(.secondary, lineWidth: 1)
                Text("N").font(.caption2).foregroundStyle(.secondary).position(x: side / 2, y: 9)
                Path { p in p.move(to: CGPoint(x: side / 2, y: side / 2)); p.addLine(to: sun) }
                    .stroke(.yellow.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Image(systemName: "sun.max.fill").foregroundStyle(.yellow).font(.system(size: 16)).position(sun)
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let dx = g.location.x - side / 2, dy = g.location.y - side / 2
                let dist = min(r, hypot(dx, dy))
                if dist > 2 {
                    var bearing = atan2(dx, -dy) * 180 / .pi
                    if bearing < 0 { bearing += 360 }
                    from = bearing.rounded()
                }
                height = (5 + 85 * (1 - dist / r)).rounded()
            })
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "From %.0f°", from)).monospacedDigit()
                Text(String(format: "Height %.0f°", height)).monospacedDigit()
                Text("North up, the building at the cross; drag the sun about it.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
