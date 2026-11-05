import SwiftUI

struct StatusLine: View {
    @Environment(Session.self) private var session

    var body: some View {
        HStack {
            if session.phase != .working {
                Text(session.choosing == .style
                    ? "The data folder's palettes, edited here: pick a colour or type its hex; a change is saved at once and shows when a tile is built again. A tile open picks one of them."
                    : session.mapEngine
                    ? "The engine's map, the archive's models over it. Drag to move, right-drag (or option-drag) to turn and tilt, scroll to zoom. Tiles are picked on the Tiles map."
                    : "Drag to move, scroll to zoom. Click picks a tile, double-click or ↩ opens it. F shows the tile picked.")
                    .lineLimit(1)
                Spacer()
            } else {
                hints
            }
            // The jobs going on are counted here, the console open or not,
            // and the job of what the window shows says how far it is.
            if let status = session.jobs.status {
                Divider().frame(height: 12)
                Text(status).lineLimit(1).foregroundStyle(.secondary)
            }
            if let job = session.contextJob, job.state.running {
                Divider().frame(height: 12)
                BuildProgress().environment(job.console).frame(maxWidth: 520, alignment: .leading)
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
        case .buildings:
            if session.pickedLandmark != nil {
                Text("The landmark's model. Drag to move, right-drag (or option-drag) to turn and tilt, scroll to zoom. F frames the model.")
                    .lineLimit(1)
                Spacer()
                Text(session.landmarkStatus).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            } else {
                Text("The tile's OSM buildings from above. Click picks one, double-click a whole building with its parts (a landmark's opens the landmark), shift adds. Drag to move, scroll to zoom, F frames.")
                    .lineLimit(1)
                Spacer()
                Text(session.buildings.hoverStatus).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
        case .preview:
            if session.workspace.previewSubject == "tile" {
                Text(session.workspace.flying
                    ? "Flight: W A S D, Q down, E up, shift faster, right-drag to look, scroll for speed. Tab to orbit."
                    : "The tile as the engine shows it. Drag to move, right-drag (or option-drag) to turn and tilt, scroll to zoom to the cursor. Tab flies, F frames.")
                    .lineLimit(1)
                Spacer()
                Text(session.workspace.tileStatus).lineLimit(1).foregroundStyle(.secondary)
            } else if session.workspace.previewSubject == "landmarks" {
                Text("All the landmarks' models where the build places them, their palette alone, no build. Drag to move, right-drag to turn and tilt, scroll to zoom. F frames.")
                    .lineLimit(1)
                Spacer()
                Text(session.previewStatus).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            } else {
                Text("The landmark alone, its light baked here. Drag to move, right-drag to turn and tilt, scroll to zoom. F frames.")
                    .lineLimit(1)
                Spacer()
                Text(session.previewStatus).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
        case .engine:
            Text("The engine's own map, the archive's models over it. Drag to move, right-drag (or option-drag) to turn and tilt, scroll to zoom.")
                .lineLimit(1)
            Spacer()
            Text(session.engineArchive?.lastPathComponent ?? "no archive").lineLimit(1).foregroundStyle(.secondary)
        case .style:
            Text("The palette every build paints with. Pick a colour or type its hex; a change is saved at once and shows when the tile is built again.")
                .lineLimit(1)
            Spacer()
            if let file = session.palette.file {
                Text(file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
        }
    }
}
