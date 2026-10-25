import Foundation

/// The folder everything the app makes lies in (its workspace: a folder a
/// tile, laid out as TileKit's WorkspacePaths). By default "Immersive Map
/// Editor Data" in the user's Application Support, where macOS apps keep
/// their data, made when first used; another can be picked in Settings.
enum DataFolder {
    static let key = "dataFolder"

    static var standard: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Immersive Map Editor Data")
    }

    /// The folder picked, else the standard one, made if it is not there.
    static var current: URL {
        let url = UserDefaults.standard.string(forKey: key).map { URL(fileURLWithPath: $0) } ?? standard
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Picks a folder, or the standard one with nil.
    static func set(_ url: URL?) {
        UserDefaults.standard.set(url?.path, forKey: key)
    }
}
