import Foundation
import ImageIO
import Observation

/// OpenStreetMap's raster tiles, from memory, from the disk cache, or
/// fetched with the User-Agent the usage policy asks for, only those on
/// screen.
@Observable
@MainActor
final class RasterTiles {
    private(set) var images: [String: CGImage] = [:]
    @ObservationIgnored private var loading = Set<String>()
    @ObservationIgnored private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ImmersiveMapEditor/osm")
    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.httpAdditionalHeaders = ["User-Agent": "ImmersiveMapEditor/0.1 (+https://github.com/artembobkin/ImmersiveMapEditor)"]
        return URLSession(configuration: config)
    }()

    /// The tile if it is here, else nil and it is on its way.
    func image(_ z: Int, _ x: Int, _ y: Int) -> CGImage? {
        let key = "\(z)/\(x)/\(y)"
        if let i = images[key] { return i }
        if !loading.contains(key) {
            loading.insert(key)
            Task { await load(key) }
        }
        return nil
    }

    /// Every tile of the list, waited for.
    func prefetch(_ tiles: [(Int, Int, Int)]) async {
        await withTaskGroup(of: Void.self) { group in
            for (z, x, y) in tiles where images["\(z)/\(x)/\(y)"] == nil {
                group.addTask { await self.load("\(z)/\(x)/\(y)") }
            }
        }
    }

    private func load(_ key: String) async {
        defer { loading.remove(key) }
        let file = folder.appendingPathComponent("\(key).png")
        var data = try? Data(contentsOf: file)
        if data == nil, let url = URL(string: "https://tile.openstreetmap.org/\(key).png"),
           let (fetched, response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fetched.write(to: file)
            data = fetched
        }
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        images[key] = image
    }
}
