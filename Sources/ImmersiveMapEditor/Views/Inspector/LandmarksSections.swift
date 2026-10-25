import SwiftUI

/// The Landmarks view's sections: the tile's landmarks (made in the
/// Buildings view, each a folder of the tile's landmarks/), to pick one and
/// see its model, its buildings and its folder.
struct LandmarksSections: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var session = session
        Section("The tile's landmarks: \(session.candidates.count)") {
            if session.candidates.isEmpty {
                Text("None yet: pick buildings in Buildings and make a landmark of them.").foregroundStyle(.secondary)
            }
            ForEach(session.candidates) { landmark in
                Button { session.pickedLandmark = landmark.id } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(landmark.name)
                        Text(verbatim: "\(landmark.buildings.count) buildings · " + (landmark.model == nil ? "no model yet" : landmark.model!.lastPathComponent))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(session.pickedLandmark == landmark.id ? Color.accentColor.opacity(0.25) : nil)
            }
        }
        if let landmark = session.candidates.first(where: { $0.id == session.pickedLandmark }) {
            Section {
                Button("Open Its Folder", systemImage: "folder") { Platform.open(landmark.folder) }
            }
        }
    }
}
