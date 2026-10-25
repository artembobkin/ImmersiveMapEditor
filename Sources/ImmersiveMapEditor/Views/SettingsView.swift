import SwiftUI

/// The app's settings (⌘,): what holds for every tile: the data folder
/// everything is kept in, and the keys the satellite imagery's sources are
/// fetched with, kept in the user's defaults.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @State private var picking = false
    @AppStorage(CameraController.invertTurningKey) private var invertTurning = true
    @AppStorage(CameraController.invertTiltingKey) private var invertTilting = false
    @AppStorage(ImagerySource.mapbox.keyName) private var mapbox = ""
    @AppStorage(ImagerySource.esri.keyName) private var esri = ""

    var body: some View {
        Form {
            Section("Data folder") {
                let root = session.workspace.root
                Text(root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.callout.monospaced()).textSelection(.enabled).lineLimit(2)
                Text("Every tile's folder (its OSM, roads and build), the landmarks' recipes and the exclusions.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Show in Finder") { Platform.open(root) }
                    Button("Choose…") { picking = true }
                    Button("Use the Standard Folder") { use(nil) }
                        .disabled(root.standardizedFileURL == DataFolder.standard.standardizedFileURL)
                }
            }
            Section("Camera") {
                Toggle("Invert turning (left and right)", isOn: $invertTurning)
                Toggle("Invert tilting (up and down)", isOn: $invertTilting)
                Text("Right-drag (or option-drag) turns and tilts the 3D views: each the other way round while it is on.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Esri World Imagery") {
                SecureField("ArcGIS key (optional)", text: $esri)
                Text("Works without a key. A key of ArcGIS Location Platform's free plan counts its use under Esri's terms.")
                    .font(.callout).foregroundStyle(.secondary)
                Link("Get a key at location.arcgis.com", destination: URL(string: "https://location.arcgis.com/")!)
                    .font(.callout)
            }
            Section("Mapbox Satellite") {
                SecureField("Mapbox token", text: $mapbox)
                Link("Get a token at mapbox.com", destination: URL(string: "https://account.mapbox.com/access-tokens/")!)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if let url = try? result.get() { use(url) }
        }
    }

    /// Keeps everything in `url` (the standard folder with nil) from now on.
    private func use(_ url: URL?) {
        DataFolder.set(url)
        session.open(workspace: DataFolder.current)
    }
}
