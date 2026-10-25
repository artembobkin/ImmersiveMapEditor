import SwiftUI

struct StatusLine: View {
    @Environment(Session.self) private var session

    var body: some View {
        HStack {
            if session.phase != .working {
                Text("Drag to move, scroll to zoom. Click picks a tile, double-click or ↩ opens it.")
                    .lineLimit(1)
                Spacer()
            } else {
                hints
            }
            // A build going on is shown here too, the console open or not.
            if session.build.running {
                Divider().frame(height: 12)
                BuildProgress().environment(session.build).frame(maxWidth: 520, alignment: .leading)
            }
        }
    }

    /// The view's hints and state.
    @ViewBuilder private var hints: some View {
        switch session.workspace.viewMode {
        case .roads:
            if let model = session.model {
                Text(model.tool.hint).lineLimit(1)
                Spacer()
                Text(model.status).lineLimit(1).foregroundStyle(.secondary)
                if model.layers.satellite {
                    let source = model.layers.imagery
                    Text(([source.name + (session.imageryCapture.map { " " + $0 } ?? "")] + [source.attribution])
                            .joined(separator: " · "))
                        .lineLimit(1).foregroundStyle(.secondary)
                        .task(id: "\(source.rawValue) \(session.workspace.tile?.name ?? "")") {
                            await session.readImageryCapture(source)
                        }
                }
            } else {
                Spacer()
            }
        case .tiles:
            Text(session.workspace.flying
                ? "Flight: W A S D, Q down, E up, shift faster, right-drag to look, scroll for speed. Tab to orbit."
                : "Drag to move, right-drag (or option-drag) to turn and tilt, scroll to zoom to the cursor. Tab flies, F frames, L light map.")
                .lineLimit(1)
            Spacer()
            Text(session.workspace.tileStatus).lineLimit(1).foregroundStyle(.secondary)
        case .landmarks:
            Text("Drag to move, right-drag (or option-drag) to turn and tilt, scroll to zoom. F frames the model.")
                .lineLimit(1)
            Spacer()
            Text(session.landmarkStatus).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
        case .light:
            Text("The tile's light map, from above. Drag to move, scroll to zoom, F frames.")
                .lineLimit(1)
            Spacer()
        }
    }
}
