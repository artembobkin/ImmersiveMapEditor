import SwiftUI

/// The app's settings (⌘,): what holds for every tile: the data folder
/// everything is kept in, the OSM extracts in it, the disk it takes, the camera, and the keys
/// the references and the satellite imagery are fetched with.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @State private var picking = false
    @AppStorage(CameraController.invertTurningKey) private var invertTurning = true
    @AppStorage(CameraController.invertTiltingKey) private var invertTilting = false
    @State private var mapillary = AgentSettings.mapillaryToken
    @AppStorage(ImagerySource.mapbox.keyName) private var mapbox = ""
    @AppStorage(ImagerySource.esri.keyName) private var esri = ""

    var body: some View {
        Form {
            Section("Data folder") {
                let root = session.workspace.root
                Text(root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.callout.monospaced()).textSelection(.enabled).lineLimit(2)
                    .help("Every tile's folder (its OSM, roads and build), the landmarks' recipes and the exclusions.")
                HStack {
                    Button("Show in Finder") { Platform.open(root) }
                    Button("Choose…") { picking = true }
                    Button("Use the Standard Folder") { use(nil) }
                        .disabled(root.standardizedFileURL == DataFolder.standard.standardizedFileURL)
                }
            }
            OsmExtractsSection(paths: session.workspace.paths)
            TidySection(tiles: session.workspace.paths.tiles)
            // The agent itself is run by the user in a terminal (the user,
            // 2026-11-20); what the editor's references and the agent's
            // tools fetch Mapillary's photos with stays here.
            Section("Landmark references") {
                SecureField("Mapillary token", text: $mapillary, prompt: Text("MLY|…  (mapillary.com/dashboard/developers)"))
                    .onChange(of: mapillary) { AgentSettings.mapillaryToken = mapillary }
                    .help("The street-level references, gathered by the editor and the agent's tools: Mapillary's photos (CC BY-SA 4.0, credited). Kept in the keychain, read by the tools from there.")
            }
            Section("Camera") {
                Toggle("Invert turning (left and right)", isOn: $invertTurning)
                    .help("Right-drag (or option-drag) turns the 3D views: the other way round while this is on.")
                Toggle("Invert tilting (up and down)", isOn: $invertTilting)
                    .help("Right-drag (or option-drag) tilts the 3D views: the other way round while this is on.")
            }
            Section("Esri World Imagery") {
                SecureField("ArcGIS key (optional)", text: $esri)
                    .help("Works without a key. A key of ArcGIS Location Platform's free plan counts its use under Esri's terms.")
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
