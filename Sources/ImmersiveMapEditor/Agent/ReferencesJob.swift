import Foundation
import Observation
import TileKit

/// A landmark's references gathered by the editor itself, as a job of the
/// session's pool: its `--gather-references` run as a process of its own
/// (the same code the agent's gather_references tool runs), its report in
/// the job's console. The street photos of every facade, the satellite view
/// and Commons' views, kept into the landmark's references/ before the user
/// starts the agent in a terminal (the user, 2026-11-20: the agents are run
/// by hand, the editor gathers and hands over the prompt). One gathering at
/// a time, for Mapillary's and Esri's limits and the shared cache, and none
/// beside another job on the same landmark.
@Observable
@MainActor
final class ReferencesJob: Job {
    let subject: JobSubject
    let title: String
    let console = Console()
    private(set) var state = JobState.queued
    private(set) var ended: Date?
    var stateChanged: () -> Void = {}
    private(set) var process: Process?
    private let folder: URL
    private var stopping = false
    /// Called when the job ends, with whether the gathering went through.
    private let then: @MainActor (Bool) -> Void

    init(tile: TileKey, id: String, name: String, folder: URL, then: @escaping @MainActor (Bool) -> Void = { _ in }) {
        subject = .landmark(tile: tile, id: id)
        title = "Gather the references of \(name)"
        self.folder = folder
        self.then = then
        console.begin(title, stage: "Queued")
    }

    var status: String {
        switch state {
        case .queued: return "queued"
        case .running: return "gathering references"
        case .done: return "references gathered" + endedStamp
        case .failed(let why): return "failed" + endedStamp + ": " + why
        case .stopped: return "stopped" + endedStamp
        }
    }

    func canStart(alongside running: [any Job]) -> Bool {
        !running.contains { $0 is ReferencesJob || $0.subject == subject }
    }

    func start() {
        guard state == .queued else { return }
        state = .running
        console.stage(name: "Gathering the references")
        console.append("The street photos of every facade, the satellite view, Commons.")
        stateChanged()
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = ["--gather-references", folder.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            console.append("Cannot gather the references: \(error.localizedDescription)")
            return end(.failed("cannot start"))
        }
        process = p
        Task {
            for await line in PipeLines.lines(of: pipe.fileHandleForReading) where !line.hasPrefix("signed ") {
                console.append("  " + line)
            }
            await Task.detached { p.waitUntilExit() }.value
            end(stopping ? .stopped : p.terminationStatus == 0 ? .done : .failed("exit \(p.terminationStatus)"))
        }
    }

    func stop() {
        guard state.active else { return }
        stopping = true
        if let process { process.terminate() } else { end(.stopped) }
    }

    private func end(_ state: JobState) {
        console.end(state == .done)
        self.state = state
        ended = Date()
        process = nil
        then(state == .done)
        stateChanged()
    }
}
