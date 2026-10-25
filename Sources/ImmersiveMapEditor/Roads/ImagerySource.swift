import Foundation

/// Where the satellite imagery under the roads comes from, picked in the
/// Roads view's layers. Each source has its tiles' address, size and
/// attribution, and the key it is fetched with, kept in the app's settings.
enum ImagerySource: String, CaseIterable, Identifiable {
    case esri, mapbox
    var id: String { rawValue }

    var name: String {
        switch self {
        case .esri: "Esri World Imagery"
        case .mapbox: "Mapbox Satellite"
        }
    }

    var attribution: String {
        switch self {
        case .esri: "© Esri, Vantor, Earthstar Geographics"
        case .mapbox: "© Mapbox © Maxar"
        }
    }

    /// The defaults key of the source's key, and whether it fetches nothing
    /// without one.
    var keyName: String {
        switch self {
        case .esri: "esri.key"
        case .mapbox: "mapbox.token"
        }
    }
    var needsKey: Bool { self == .mapbox }
    var key: String { UserDefaults.standard.string(forKey: keyName) ?? "" }

    /// Texels across one of its tiles.
    var tileTexels: Double {
        switch self {
        case .esri: 256
        case .mapbox: 512
        }
    }

    /// A tile's address, nil when the source needs a key it has not.
    func url(z: Int, x: Int, y: Int) -> URL? {
        let key = self.key
        if needsKey && key.isEmpty { return nil }
        switch self {
        case .esri:
            // Rows before columns in Esri's addresses. The key is optional:
            // ArcGIS Location Platform's, for its terms and its counts.
            let token = key.isEmpty ? "" : "?token=\(key)"
            return URL(string: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/\(z)/\(y)/\(x)\(token)")
        case .mapbox:
            return URL(string: "https://api.mapbox.com/v4/mapbox.satellite/\(z)/\(x)/\(y)@2x.jpg90?access_token=\(key)")
        }
    }

    /// When and how sharp the imagery at a point was taken, from the source's
    /// metadata, as "2025-06-16, 0.34 m, Vantor". Only Esri says it.
    func capture(latitude: Double, longitude: Double) async -> String? {
        guard self == .esri else { return nil }
        let (lon, lat) = (String(format: "%.6f", longitude), String(format: "%.6f", latitude))
        let around = String(format: "%.5f,%.5f,%.5f,%.5f", longitude - 0.01, latitude - 0.01, longitude + 0.01, latitude + 0.01)
        guard let url = URL(string: "https://services.arcgisonline.com/arcgis/rest/services/World_Imagery/MapServer/identify"
                            + "?geometry=\(lon),\(lat)&geometryType=esriGeometryPoint&sr=4326&layers=all&tolerance=1"
                            + "&mapExtent=\(around)&imageDisplay=800,600,96&returnGeometry=false&f=json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }
        for r in results {
            guard let a = r["attributes"] as? [String: Any], let date = a["SRC_DATE"] as? String, date.count == 8 else { continue }
            let day = "\(date.prefix(4))-\(date.dropFirst(4).prefix(2))-\(date.suffix(2))"
            let res = a["SRC_RES"].map { "\($0) m" }
            let source = a["NICE_DESC"] as? String
            return ([day] + [res, source].compactMap { $0 }).joined(separator: ", ")
        }
        return nil
    }
}
