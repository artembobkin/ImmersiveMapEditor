import SwiftUI

/// The app's settings (⌘,): what holds for every tile: the data folder
/// everything is kept in, and the keys the satellite imagery's sources are
/// fetched with, kept in the user's defaults.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @State private var picking = false
    @AppStorage(CameraController.invertTurningKey) private var invertTurning = true
    @AppStorage(CameraController.invertTiltingKey) private var invertTilting = false
    @AppStorage(ClaudeSettings.executableKey) private var claudePath = ""
    @AppStorage(ClaudeSettings.modelKey) private var claudeModel = ""
    @AppStorage(ClaudeSettings.effortKey) private var claudeEffort = ""
    @AppStorage(ClaudeSettings.detailKey) private var claudeDetail = "normal"
    /// The proxy, edited here and kept in the keychain (never shown in full).
    @State private var proxy = ClaudeSettings.proxy
    @State private var noProxy = ClaudeSettings.noProxy
    @State private var mapillary = ClaudeSettings.mapillaryToken
    @State private var proxySaid = ""
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
            Section("Claude") {
                TextField("claude", text: $claudePath, prompt: Text(ClaudeSettings.executable?.path ?? "~/.local/bin/claude"))
                // Lists, not text (the user, 2026-11-04: a typo in a text
                // field was asked of claude as a model, and every run failed).
                Picker("Model", selection: Binding(get: { ClaudeSettings.model }, set: { claudeModel = $0 })) {
                    ForEach(ClaudeSettings.models, id: \.id) { Text($0.title).tag($0.id) }
                }
                .help("Which Claude models the landmarks: Claude Code's default, or one by name.")
                Picker("Effort", selection: Binding(get: { ClaudeSettings.effort }, set: { claudeEffort = $0 })) {
                    ForEach(ClaudeSettings.efforts, id: \.id) { Text($0.title).tag($0.id) }
                }
                .help("How hard it thinks: Claude Code's default, or a level.")
                Picker("Detail", selection: Binding(get: { ClaudeSettings.detail }, set: { claudeDetail = $0 })) {
                    ForEach(ClaudeSettings.details, id: \.id) { Text($0.title).tag($0.id) }
                }
                .help("How much of a landmark Claude models: everything that reads from across the street, or the ornament too (slower and dearer). Each landmark keeps the level it is queued with.")
                SecureField("Proxy (HTTP_PROXY, HTTPS_PROXY, ALL_PROXY)", text: $proxy)
                    .onSubmit { ClaudeSettings.proxy = proxy }
                    .onChange(of: proxy) { ClaudeSettings.proxy = proxy }
                    .help("The landmarks' agent runs Claude Code on your subscription, every request through this proxy. The proxy is kept in your keychain, never in the project.")
                SecureField("No proxy (NO_PROXY)", text: $noProxy)
                    .onChange(of: noProxy) { ClaudeSettings.noProxy = noProxy }
                SecureField("Mapillary token", text: $mapillary, prompt: Text("MLY|…  (mapillary.com/dashboard/developers)"))
                    .onChange(of: mapillary) { ClaudeSettings.mapillaryToken = mapillary }
                    .help("The agent's street-level references: Mapillary's photos (CC BY-SA 4.0, credited). Kept in the keychain.")
                HStack {
                    Button("Take from ~/bin/claude") {
                        let launcher = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin/claude")
                        if ClaudeSettings.takeProxy(fromLauncher: launcher) {
                            proxy = ClaudeSettings.proxy
                            noProxy = ClaudeSettings.noProxy
                            proxySaid = "Taken from ~/bin/claude."
                        } else {
                            proxySaid = "No proxy in ~/bin/claude."
                        }
                    }
                    Text(proxySaid).font(.callout).foregroundStyle(.secondary)
                }
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
