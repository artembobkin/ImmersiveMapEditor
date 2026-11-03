import Foundation
import Observation
import TileKit

/// What a job is about, so the console at the foot of the window shows the
/// job of what the window shows (the user, 2026-11-02: a build belongs to
/// the tile it builds, Claude's run to its landmark): a tile (its builds,
/// bakes, fetches and seeds), a landmark of a tile (Claude on it, its model
/// built from its recipe), or the whole data folder (the archive).
enum JobSubject: Hashable {
    case tile(TileKey)
    case landmark(tile: TileKey, id: String)
    case workspace
}

enum JobState: Equatable {
    case queued, running, done, stopped
    /// With why: what the console's last lines say in a few words.
    case failed(String)
    /// Whether the job still has work to do or is doing it.
    var active: Bool { self == .queued || self == .running }
    var running: Bool { self == .running }
    var isFailed: Bool { if case .failed = self { true } else { false } }
}

/// A piece of work run from the editor with a log of its own: a pipeline
/// command on a tile (`PipelineJob`), Claude on a landmark (`LandmarkRun`).
/// Jobs are queued in the `JobPool`, which starts each when its own rule
/// allows it (`canStart`), so several run at once, and keeps the ended ones
/// for their logs. A new kind of work is a new type conforming to this,
/// with its own rule, never a branch in the pool (the user, 2026-11-02).
@MainActor
protocol Job: AnyObject, Observable {
    var subject: JobSubject { get }
    /// What it is, for the console's title: "Build 15/19808/10242".
    var title: String { get }
    var console: Console { get }
    var state: JobState { get }
    /// What the state is in a few words, for lists: "queued", "done 15:24".
    var status: String { get }
    var ended: Date? { get }
    /// Whether it may start now beside the jobs running: how many of its
    /// own kind run at once, what it must not run beside.
    func canStart(alongside running: [any Job]) -> Bool
    func start()
    func stop()
    /// Set by the pool: called whenever the state changes, so the next
    /// queued job can start.
    var stateChanged: () -> Void { get set }
}

extension Job {
    /// The time it ended, for a status: " 15:24".
    var endedStamp: String {
        guard let ended else { return "" }
        return " " + ended.formatted(date: .omitted, time: .shortened)
    }
}
