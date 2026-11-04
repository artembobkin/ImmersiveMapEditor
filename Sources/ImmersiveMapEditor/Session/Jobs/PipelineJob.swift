import Foundation
import Observation

/// The pipeline (the editor itself, as `ImmersiveMapEditor pipeline`,
/// TileKit's PipelineCommand: the same build, never older) run on the data
/// folder as a job: its commands one after another, stopping at the first
/// that fails, their output into its console as it comes, their progress
/// lines into the console's stage. Two commands never run on one subject
/// at once (a bake waits for its tile's build), and at most `atOnce`
/// pipelines run together: a build takes every core and the GPU.
@Observable
@MainActor
final class PipelineJob: Job {
    static let atOnce = 2

    let subject: JobSubject
    let title: String
    let console = Console()
    private(set) var state = JobState.queued
    private(set) var ended: Date?
    var stateChanged: () -> Void = {}
    private let root: URL
    private let steps: [[String]]
    /// Called when the job ends, with whether every command went through.
    private let then: @MainActor (Bool) -> Void
    private(set) var process: Process?
    private var stopping = false
    /// Whether the job goes on past a command that failed, for commands
    /// that stand apart (a fetch a tile), and reports them at the end.
    private let goOn: Bool
    /// What each command came to, in order: its arguments, whether it went
    /// through, and the pipeline's last word on it when it did not (the
    /// user, 2026-11-04: the fetch of many tiles told from the panel).
    private(set) var results: [(arguments: [String], ok: Bool, note: String?)] = []
    /// The command going now.
    private(set) var current: [String]?
    private var lastWord: String?

    init(subject: JobSubject, title: String, root: URL, steps: [[String]], goOn: Bool = false,
         then: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.subject = subject
        self.title = title
        self.root = root
        self.steps = steps
        self.goOn = goOn
        self.then = then
        console.begin(title, stage: "Queued")
    }

    var status: String {
        switch state {
        case .queued: return "queued"
        case .running: return console.stage?.name ?? "running"
        case .done: return "done" + endedStamp
        case .failed(let why): return "failed" + endedStamp + ": " + why
        case .stopped: return "stopped" + endedStamp
        }
    }

    func canStart(alongside running: [any Job]) -> Bool {
        let pipelines = running.compactMap { $0 as? PipelineJob }
        return !pipelines.contains { $0.subject == subject } && pipelines.count < Self.atOnce
    }

    func start() {
        guard state == .queued else { return }
        state = .running
        console.stage(nil)
        stateChanged()
        Task {
            var ok = true
            var exit: Int32 = 0
            for (i, arguments) in steps.enumerated() where (ok || goOn) && !stopping {
                console.step(i + 1, of: steps.count)
                current = arguments
                lastWord = nil
                exit = await run(arguments)
                results.append((arguments, exit == 0, exit == 0 ? nil : lastWord))
                ok = ok && exit == 0
            }
            current = nil
            let failed = results.filter { !$0.ok }.count
            end(stopping ? .stopped : ok ? .done : .failed(goOn ? "\(failed) of \(results.count) failed" : "exit \(exit)"))
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

    /// One command, its output into the console as it comes, its progress
    /// lines into the stage; its exit code, or -1 when it could not start.
    private func run(_ arguments: [String]) async -> Int32 {
        console.append("$ pipeline \(arguments.joined(separator: " "))")
        let tool = Bundle.main.executableURL!
        let p = Process()
        p.executableURL = tool
        p.arguments = ["pipeline", "--root", root.path] + arguments
        p.environment = ProcessInfo.processInfo.environment.merging(ClaudeSettings.generatorEnvironment) { _, new in new }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            console.append("Cannot start \(tool.path): \(error.localizedDescription)")
            return -1
        }
        process = p
        for await line in PipeLines.lines(of: pipe.fileHandleForReading) {
            if line.hasPrefix("@progress "), let s = Console.stage(progress: line.dropFirst(10)) {
                console.stage(s)
            } else {
                if line.hasPrefix("pipeline: ") { lastWord = String(line.dropFirst(10)) }
                console.append(line)
            }
        }
        await Task.detached { p.waitUntilExit() }.value
        if p.terminationStatus != 0 { console.append("Failed (\(p.terminationStatus)).") }
        return p.terminationStatus
    }
}
