import Foundation

/// A finished landmark's working files removed, the files it can make again
/// whenever it is worked on, to free the disk (the user, 2026-11-22: the
/// data of every tile grew and no one cleared it). Measured on the data
/// folder then: of its 10 GB of tiles, 3.9 GB were the candidates the agent
/// was shown (`search/`, JPEGs, which zip would make 2% smaller) and 2.8 GB
/// its rounds (a copy of the model of every build and the comparisons after
/// it). So nothing is packed, to be unpacked later: what goes is what the
/// tools make again, and what the work goes on from stays.
///
/// - Goes: `search/` whole; in every `rounds/NN/`, all but its recipe and
///   its summary (the round's model, its renders and comparisons).
/// - Stays: the model and the recipe at the top, the references the agent
///   chose (`references/`), every round's recipe and summary (so the next
///   build compares with the last recipe and takes the next number), and
///   the landmark itself.
///
/// Only a landmark with a model is tidied: one still being made keeps all.
enum LandmarkTidy {
    /// The files of a round that stay: its recipe, its summary, its reviews.
    static func stays(_ file: URL) -> Bool { ["json", "txt"].contains(file.pathExtension.lowercased()) }

    /// What tidying the landmark in `folder` would remove: nothing when it
    /// has no model yet.
    static func disposable(_ folder: URL) -> [URL] {
        guard TileLandmark.model(in: folder) != nil else { return [] }
        let fm = FileManager.default
        var out: [URL] = []
        let search = folder.appendingPathComponent("search")
        if fm.fileExists(atPath: search.path) { out.append(search) }
        let rounds = folder.appendingPathComponent("rounds")
        for round in (try? fm.contentsOfDirectory(at: rounds, includingPropertiesForKeys: nil)) ?? [] where Int(round.lastPathComponent) != nil {
            for item in (try? fm.contentsOfDirectory(at: round, includingPropertiesForKeys: nil)) ?? [] where !stays(item) {
                out.append(item)
            }
        }
        return out
    }

    /// The bytes tidying the landmark would free.
    static func reclaimable(_ folder: URL) -> Int { disposable(folder).reduce(0) { $0 + size(of: $1) } }

    /// The landmark tidied; the bytes freed.
    @discardableResult
    static func tidy(_ folder: URL) -> Int {
        var freed = 0
        for item in disposable(folder) {
            let bytes = size(of: item)
            if (try? FileManager.default.removeItem(at: item)) != nil { freed += bytes }
        }
        return freed
    }

    /// Every landmark of a tile's `landmarks/` folder tidied; the landmarks
    /// tidied and the bytes freed.
    static func tidyTile(_ landmarks: URL) -> (landmarks: Int, freed: Int) {
        var count = 0, freed = 0
        for folder in landmarkFolders(landmarks) {
            let bytes = tidy(folder)
            if bytes > 0 { count += 1; freed += bytes }
        }
        return (count, freed)
    }

    /// The landmark folders of a tile's `landmarks/`.
    static func landmarkFolders(_ landmarks: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: landmarks, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("landmark.json").path) }
    }

    /// Every tile's `landmarks/` folder of the data folder at `tiles`.
    static func tileLandmarkFolders(_ tiles: URL) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for z in (try? fm.contentsOfDirectory(at: tiles, includingPropertiesForKeys: nil)) ?? [] {
            for x in (try? fm.contentsOfDirectory(at: z, includingPropertiesForKeys: nil)) ?? [] {
                for y in (try? fm.contentsOfDirectory(at: x, includingPropertiesForKeys: nil)) ?? [] {
                    let landmarks = y.appendingPathComponent("landmarks")
                    if fm.fileExists(atPath: landmarks.path) { out.append(landmarks) }
                }
            }
        }
        return out
    }

    /// The bytes a file or a folder takes on the disk.
    static func size(of url: URL) -> Int {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return values.totalFileAllocatedSize ?? 0 }
        var total = 0
        let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let item = walk?.nextObject() as? URL {
            total += (try? item.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0
        }
        return total
    }

    /// Bytes as people read them: 812 MB, 3.4 GB.
    static func text(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
