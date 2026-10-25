import SwiftUI

struct StatusLine: View {
    @Environment(Session.self) private var session

    var body: some View {
        HStack {
            switch session.workspace.viewMode {
            case .map:
                Text("Drag to move, scroll to zoom. Click picks a tile, shift-drag a box of them, double-click shows a built one in 3D.")
                    .lineLimit(1)
                Spacer()
            case .roads:
                if let model = session.model {
                    Text(model.tool.hint).lineLimit(1)
                    Spacer()
                    Text(model.status).lineLimit(1).foregroundStyle(.secondary)
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
            }
            // A build going on is shown here too, the log open or not.
            if session.build.running {
                Divider().frame(height: 12)
                ProgressView().controlSize(.mini)
                Text(session.build.lastLine).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360, alignment: .leading)
            }
        }
    }
}
