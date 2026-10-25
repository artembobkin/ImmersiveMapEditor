import SwiftUI

/// The app's settings (⌘,): what holds for every workspace and tile, such as
/// the keys the satellite imagery's sources are fetched with, kept in the
/// user's defaults.
struct SettingsView: View {
    @AppStorage(ImagerySource.mapbox.keyName) private var mapbox = ""
    @AppStorage(ImagerySource.esri.keyName) private var esri = ""

    var body: some View {
        Form {
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
        .frame(width: 480)
    }
}
