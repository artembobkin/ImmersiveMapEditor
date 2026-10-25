import SwiftUI

/// The Light view's sections: the bake's settings and the bake of the
/// working tile, again, without building their geometry (`pipeline bake`).
struct LightSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var light = session.lightSettings
        let workspace = session.workspace
        let built = workspace.shown
        Section("Bake settings") {
            Picker("Light map", selection: $light.size) {
                ForEach([512, 1024, 2048], id: \.self) { Text("\($0) px a tile").tag($0) }
            }
            Picker("Samples", selection: $light.samples) {
                ForEach([64, 128, 256, 512, 1024], id: \.self) { Text("\($0)").tag($0) }
            }
            Stepper("Bounces: \(light.bounces)", value: $light.bounces, in: 0...6)
        }
        Section("Light map") {
            ForEach(built, id: \.self) { t in
                if let map = session.lights.maps[t] {
                    LabeledContent {
                        Text(map.baked ? "\(map.px) px, overhang \(map.overhang, specifier: "%.0f") m" : "not baked yet")
                            .monospacedDigit().foregroundStyle(.secondary)
                    } label: {
                        Text(verbatim: t.name).font(.callout.monospaced())
                    }
                } else {
                    Text(verbatim: t.name).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }
}
