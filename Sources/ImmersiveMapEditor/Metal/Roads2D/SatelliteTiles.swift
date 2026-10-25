import Foundation
import MetalKit

/// The satellite imagery under the road document, so a road can be checked
/// against where it really is: the tiles of the source picked (ImagerySource)
/// in view, fetched with its key from the app's settings and kept in
/// URLSession's cache, as the sources' terms allow.
@MainActor
final class SatelliteTiles {
    struct Tile: Hashable { let source: ImagerySource, z, x, y: Int }

    private let device: MTLDevice
    private let loader: MTKTextureLoader
    private var textures: [Tile: MTLTexture] = [:]
    private var loading = Set<Tile>()
    private var failed = Set<Tile>()
    /// The keys the failures were met with: a new one tries them again.
    private var failedWith: [ImagerySource: String] = [:]
    /// Called when a tile arrives, to draw again.
    var arrived: () -> Void = {}
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20, directory:
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ImmersiveMapEditor/imagery"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = ["User-Agent": "ImmersiveMapEditor/0.1 (+https://github.com/artembobkin/ImmersiveMapEditor)"]
        return URLSession(configuration: config)
    }()

    init(device: MTLDevice) {
        self.device = device
        loader = MTKTextureLoader(device: device)
    }

    /// The texture of a tile if it is here, else nil and it is on its way.
    func texture(_ t: Tile) -> MTLTexture? {
        if let tex = textures[t] { return tex }
        let key = t.source.key
        if failedWith[t.source] != key {
            failed = failed.filter { $0.source != t.source }
            failedWith[t.source] = key
        }
        guard !loading.contains(t), !failed.contains(t), let url = t.source.url(z: t.z, x: t.x, y: t.y) else { return nil }
        loading.insert(t)
        Task { await load(t, url) }
        return nil
    }

    private func load(_ t: Tile, _ url: URL) async {
        defer { loading.remove(t) }
        guard let (data, response) = try? await session.data(from: url),
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
