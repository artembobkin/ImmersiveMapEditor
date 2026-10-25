import SwiftUI

/// The Light view's panel: the bake's settings and the bake of the tiles
/// picked, again, without building their geometry (`tilepipeline bake`).
struct LightPanel: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var light = session.lightSettings
        let workspace = session.workspace
        let built = workspace.selection.sorted().filter { workspace.built.contains($0) }
        Form {
            Section("Bake") {
                Picker("Light map", selection: $light.size) {
                    ForEach([512, 1024, 2048], id: \.self) { Text("\($0) px a tile").tag($0) }
                }
                Picker("Samples", selection: $light.samples) {
                    ForEach([64, 128, 256, 512, 1024], id: \.self) { Text("\($0)").tag($0) }
                }
                Stepper("Bounces: \(light.bounces)", value: $light.bounces, in: 0...6)
                Button("Bake Light (\(built.count) tiles)") { session.bake(built) }
                    .disabled(built.isEmpty || session.build.running)
                Text("Bakes the light map of the tiles picked again, their geometry as built. A tile builds once before it bakes.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Tiles: \(built.count) built") {
                ForEach(built, id: \.self) { t in
                    if let map = session.lights.maps[t] {
                        LabeledContent {
                            Text("\(map.px) px, overhang \(map.overhang, specifier: "%.0f") m")
                                .monospacedDigit().foregroundStyle(.secondary)
                        } label: {
                            Text(verbatim: "\(t.x)/\(t.y)").font(.callout.monospaced())
                        }
                    } else {
                        Text(verbatim: "\(t.x)/\(t.y)").font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
