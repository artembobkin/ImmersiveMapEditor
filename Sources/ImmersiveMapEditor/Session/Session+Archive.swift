import Foundation
import ImmersiveMap
import TileKit

/// The engine's model archive: every built tile archived anew into
/// engine/, the changed tiles built first, and exported where the user
/// chooses.
extension Session {
    /// Every built tile whose inputs changed built again (`--changed`), and
    /// the tile open when it has its OSM and was never built, then all of
    /// them into a new archive in engine/, the older ones gone after it, and
    /// the Engine view over it: a model rebuilt from its recipe reaches the
    /// engine without a build of its own (the user, 2026-11-21).
    func updateEngineArchive() {
        var tiles = workspace.built
        if let tile = workspace.tile, workspace.fetched.contains(tile) { tiles.insert(tile) }
        archive(building: tiles.sorted { ($0.x, $0.y) < ($1.x, $1.y) }, exportTo: nil, title: "Update the engine's archive")
    }

    /// Whether every tile can be built and archived now: some tile has its
    /// OSM, and no job of the data folder is going.
    var canBuildAll: Bool { phase != .preparing && !workspace.fetched.isEmpty && !jobs.isActive(.workspace) }

    /// Every tile with its OSM whose inputs changed since its last build
    /// built again with the parts chosen (`--changed`, `BuildInputs`), the
    /// others left as they are, then archived, the archive baking only the
    /// tiles whose builds changed (`ArchiveCache`), in one job of the data
    /// folder (the user, 2026-11-20: building tile by tile and exporting
    /// apart was too much, and building everything again each time too
    /// long): the
    /// engine's archive in engine/ made anew for the Engine view, and a
    /// copy of it where the user chooses, the place remembered. A tile that
    /// fails to build is named at the end, and the others are archived.
    func buildAllAndExport() {
        guard canBuildAll else { return }
        let remembered = UserDefaults.standard.string(forKey: Self.exportKey).map { URL(fileURLWithPath: $0) }
        let suggested = remembered ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").appendingPathComponent("models.pmtiles")
        guard let destination = Platform.chooseSaveLocation(suggested: suggested, title: "Build Changed Tiles and Export",
                                                            message: "Every tile whose OSM, landmarks or palette changed is built again, then all are archived here in the form the engine reads.") else { return }
        UserDefaults.standard.set(destination.path, forKey: Self.exportKey)
        let tiles = workspace.fetched.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        archive(building: tiles, exportTo: destination, title: "Build the changed of \(tiles.count) tiles and export the archive")
    }
    private static let exportKey = "archive.exportPath"

    /// One job of the data folder: the `tiles` built, one command each, the
    /// job going on past a tile that fails; then every built tile archived
    /// into a new file of engine/, the older ones dropped once it is
    /// written, and copied to `exportTo` when given.
    func archive(building tiles: [TileKey], exportTo destination: URL?, title: String) {
        let stamp = Date().formatted(.verbatim("\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)", locale: .init(identifier: "en_US_POSIX"), timeZone: .current, calendar: .init(identifier: .gregorian)))
        let folder = engineFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent("models-\(stamp).pmtiles")
        model?.saveIfNeeded()
        let workspace = self.workspace
        var job: PipelineJob?
        job = PipelineJob(subject: .workspace, title: title, root: workspace.root,
                          steps: tiles.map { buildStep($0) + ["--changed"] } + [["archive", out.path]], goOn: !tiles.isEmpty) { [weak self] _ in
            workspace.scan()
            workspace.tilesRevision += 1
            // The archive's own command decides, whatever the builds before it.
            let archived = job?.results.last.map { $0.ok && $0.arguments.first == "archive" } ?? false
            if archived {
                for old in ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                    where old.pathExtension == "pmtiles" && old.lastPathComponent != out.lastPathComponent {
                    try? FileManager.default.removeItem(at: old)
                }
                if let destination {
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                        try FileManager.default.copyItem(at: out, to: destination)
                        job?.console.append("Exported to \(destination.path)")
                    } catch {
                        job?.console.append("Cannot export to \(destination.path): \(error.localizedDescription)")
                        self?.problem = "The archive was made but could not be copied to \(destination.path): \(error.localizedDescription)"
                    }
                }
            }
            if let failed = job?.results.filter({ !$0.ok && $0.arguments.first == "build" }), !failed.isEmpty {
                job?.console.append("Not built: " + failed.map { "\($0.arguments[1])/\($0.arguments[3])" + ($0.note.map { " (\($0))" } ?? "") }.joined(separator: ", "))
            }
            self?.engineRevision += 1
            job = nil
        }
        if let job { jobs.add(job) }
    }

    /// Every built tile into the engine's model archive, where the user
    /// chooses (the user, 2026-10-29).
    func exportArchive() {
        let remembered = UserDefaults.standard.string(forKey: Self.exportKey).map { URL(fileURLWithPath: $0) }
        let suggested = remembered ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").appendingPathComponent("models.pmtiles")
        guard let url = Platform.chooseSaveLocation(suggested: suggested, title: "Export the Model Archive",
                                                    message: "Every built tile, in the form the engine reads (a PMTiles archive of model tiles).") else { return }
        UserDefaults.standard.set(url.path, forKey: Self.exportKey)
        run([["archive", url.path]], on: .workspace, title: "Export the archive")
    }
}
