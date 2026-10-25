import SwiftUI

/// The app's settings (⌘,): what holds for every workspace and tile, such as
/// the Mapbox token the satellite imagery is fetched with, kept in the
/// user's defaults. A public token (pk.) of a free Mapbox account will do.
struct SettingsView: View {
    @AppStorage(SatelliteTiles.tokenKey) private var token = ""

    var body: some View {
        Form {
            Section("Satellite imagery") {
                SecureField("Mapbox token", text: $token)
                Link("Get a token at mapbox.com", destination: URL(string: "https://account.mapbox.com/access-tokens/")!)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
