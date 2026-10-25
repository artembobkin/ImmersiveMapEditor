import Foundation
import MetalKit

/// Mapbox's satellite imagery under the road document, so a road can be
/// checked against where it really is: the tiles in view at the zoom that
/// matches the screen, fetched with the user's token (the app's Settings)
/// and kept in URLSession's cache, as Mapbox's terms allow.
@MainActor
final class SatelliteTiles {
    static let tokenKey = "mapbox.token"
    static var token: String { UserDefaults.standard.string(forKey: tokenKey) ?? "" }

    struct Tile: Hashable { let z, x, y: Int }

    private let device: MTLDevice
    private let loader: MTKTextureLoader
    private var textures: [Tile: MTLTexture] = [:]
    private var loading = Set<Tile>()
    private var failed = Set<Tile>()
    /// The token the failures were met with: a new one tries them again.
    private var failedWith = ""
    /// Called when a tile arrives, to draw again.
    var arrived: () -> Void = {}
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20, directory:
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ImmersiveMapEditor/mapbox"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    init(device: MTLDevice) {
        self.device = device
        loader = MTKTextureLoader(device: device)
    }

    /// The texture of a tile if it is here, else nil and it is on its way.
    func texture(_ t: Tile) -> MTLTexture? {
        if let tex = textures[t] { return tex }
        let token = Self.token
        if token != failedWith {
            failed.removeAll()
            failedWith = token
        }
        guard !token.isEmpty, !loading.contains(t), !failed.contains(t) else { return nil }
        loading.insert(t)
        Task { await load(t, token: token) }
        return nil
    }

    private func load(_ t: Tile, token: String) async {
        defer { loading.remove(t) }
        guard let url = URL(string: "https://api.mapbox.com/v4/mapbox.satellite/\(t.z)/\(t.x)/\(t.y)@2x.jpg90?access_token=\(token)"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let tex = try? await loader.newTexture(data: data, options: [.SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
        else {
            failed.insert(t)
            return
        }
        // Few tiles are in view at once: keep a few hundred, the oldest go.
        if textures.count > 400 { textures.removeAll() }
        textures[t] = tex
        arrived()
    }
}
