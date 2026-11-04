import Foundation
import Observation
import TileKit

/// A place on the map a tile is chosen on, kept by name to come back to:
/// where the camera was and how far in (the user, 2026-11-04: a way to type
/// a latitude and longitude or a tile's number and be there at once, and
/// to keep such points for a list).
struct Place: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var zoom: Double
}

/// The places kept, in the data folder's `config/places.json`: the user's,
/// so they go with the data folder, as the palette does.
@Observable
@MainActor
final class Places {
    private(set) var all: [Place] = []
    private var file: URL?

    func load(_ paths: WorkspacePaths) {
        file = paths.config.appendingPathComponent("places.json")
        all = (try? JSONDecoder().decode([Place].self, from: Data(contentsOf: file!))) ?? []
    }

    func add(_ place: Place) {
        all.append(place)
        save()
    }

    func remove(_ place: Place) {
        all.removeAll { $0.id == place.id }
        save()
    }

    private func save() {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(all).write(to: file, options: .atomic)
    }

    /// What a typed destination means: a tile "15/19808/10243", or a
    /// latitude and longitude "55.7539, 37.6208" (longitude first taken as
    /// such when the first number is past 90, a latitude's limit); nil for
    /// anything else.
    enum Destination: Equatable {
        case tile(TileKey)
        case point(latitude: Double, longitude: Double)
    }

    static func destination(_ text: String) -> Destination? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let slashes = trimmed.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        if slashes.count == 3, let z = Int(slashes[0]), let x = Int(slashes[1]), let y = Int(slashes[2]), (0...22).contains(z),
           x >= 0, y >= 0, x < 1 << z, y < 1 << z {
            return .tile(TileKey(z: z, x: x, y: y))
        }
        let numbers = trimmed.split { $0 == "," || $0 == " " || $0 == ";" }.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 2 else { return nil }
        var (lat, lon) = (numbers[0], numbers[1])
        if abs(lat) > 90, abs(lon) <= 90 { swap(&lat, &lon) }
        guard abs(lat) <= 85, abs(lon) <= 180 else { return nil }
        return .point(latitude: lat, longitude: lon)
    }
}
