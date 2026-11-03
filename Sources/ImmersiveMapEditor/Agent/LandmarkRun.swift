import Foundation
import Observation
import TileKit

/// One run of Claude on one landmark, a job of the session's pool: its
/// state, its own console (the log the bottom panel shows while the
/// landmark is open) and its process. A new attempt gathers the references
/// first, with no agent (the user, 2026-10-28), then launches Claude Code;
/// a request goes on with the landmark's conversation. Its rule in the
/// pool: at most `ClaudeSettings.atOnce` runs at once, and one of them
/// gathering (Mapillary's and Esri's limits, the shared cache), so several
/// landmarks are modelled at once (the user, 2026-11-01).
@Observable
@MainActor
final class LandmarkRun: Job {
    enum Phase { case gathering, modelling }

    /// The landmark's id: its folder's name.
    let id: String
    let name: String
    let folder: URL
    let subject: JobSubject
    /// A request to go on with, or nil for a new attempt from OSM.
    let request: String?
    let console = Console()
    private(set) var state = JobState.queued
    /// What a running run is at.
    private(set) var phase = Phase.gathering
    private(set) var ended: Date?
    private var process: Process?
    private var stopping = false
    /// Called when the run may have built a new model, and when it ends.
    var modelChanged: () -> Void = {}
    /// Called when the state changes (the references gathered, the run
    /// ended), for the pool to start the next.
    var stateChanged: () -> Void = {}

    init(tile: TileKey, id: String, name: String, folder: URL, request: String?) {
        self.id = id
        self.name = name
        self.folder = folder
        self.request = request
        subject = .landmark(tile: tile, id: id)
        console.begin(title, stage: "Queued")
        console.append("Waiting for a free slot: \(ClaudeSettings.atOnce) at once (Claude's settings).")
    }

    var title: String { "Claude: \(name)" }

    /// What the state is, for the list of landmarks.
    var status: String {
        switch state {
        case .queued: return "queued"
        case .running: return phase == .gathering ? "gathering references" : "Claude is modelling"
        case .done: return "done" + endedStamp
        case .failed(let why): return "failed" + endedStamp + ": " + why
        case .stopped: return "stopped" + endedStamp
        }
    }

    func canStart(alongside running: [any Job]) -> Bool {
        let runs = running.compactMap { $0 as? LandmarkRun }
        guard runs.count < ClaudeSettings.atOnce else { return false }
        return request != nil || !runs.contains { $0.phase == .gathering }
    }

    /// Starts the run: the references first for a new attempt.
    func start() {
        guard state == .queued else { return }
        guard let claude = ClaudeSettings.executable else {
            end(.failed("no claude"), "No claude found: set its path in Settings > Claude.")
            return
        }
        guard !ClaudeSettings.proxy.isEmpty else {
            end(.failed("no proxy"), "No proxy set: Claude Code must go through the proxy. Settings > Claude.")
            return
        }
        if request == nil {
            LandmarkAgent.startOver(folder)
            modelChanged()
            phase = .gathering
            state = .running
            stateChanged()
            console.stage(name: "Gathering the references of \(name)")
            gather { [weak self] in
                guard let self, !self.stopping else { self?.end(.stopped); return }
                self.launch(claude)
            }
        } else {
            launch(claude)
        }
    }

    func stop() {
        guard state.active else { return }
        stopping = true
        if let process { process.terminate() } else { end(.stopped) }
    }

    private func end(_ state: JobState, _ message: String? = nil) {
        if let message { console.append(message) }
        self.state = state
        ended = Date()
        process = nil
        console.end(state == .done)
        // The log kept in the folder (agent.log), and Claude Code's raw
        // stream (agent.stream.jsonl) only when the run went wrong: the
        // evidence of why (the user, 2026-11-01: "failed" with no reason).
        try? console.log.write(to: folder.appendingPathComponent("agent.log"), atomically: true, encoding: .utf8)
        try? stream?.close()
        stream = nil
        if state == .done { try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.streamName)) }
        modelChanged()
        stateChanged()
    }

    static let streamName = "agent.stream.jsonl"
    /// Claude Code's stream as it comes, written line by line.
    private var stream: FileHandle?

    /// The references of a landmark gathered by the editor itself (its
    /// --gather-references, the same code the agent's tools run), its
    /// report in the console; then `done`.
    private func gather(done: @escaping @MainActor () -> Void) {
        console.append("Gathering the references: the street photos of every facade, the satellite view, Commons.")
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = ["--gather-references", folder.path]
        p.environment = ClaudeSettings.environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            console.append("Cannot gather the references: \(error.localizedDescription)")
            done()
            return
        }
        process = p
        Task {
            for await line in PipeLines.lines(of: pipe.fileHandleForReading) where !line.hasPrefix("signed ") {
                console.append("  " + line)
            }
            await Task.detached { p.waitUntilExit() }.value
            process = nil
            done()
        }
    }

    private func launch(_ claude: URL) {
        var args = ["-p", request ?? LandmarkAgent.firstRequest(name), "--output-format", "stream-json", "--verbose",
                    "--tools", "WebSearch,WebFetch",
                    "--allowedTools", "WebSearch,WebFetch,mcp__landmark",
                    "--permission-mode", "dontAsk",
                    "--strict-mcp-config", "--mcp-config", LandmarkAgent.mcpConfig(folder),
                    "--append-system-prompt", LandmarkAgent.system]
        if let model = UserDefaults.standard.string(forKey: ClaudeSettings.modelKey), !model.isEmpty {
            args += ["--model", model]
        }
        // The safety stop on the turns: the plan fits in well under it.
        let turns = ClaudeSettings.maxTurns(facades: LandmarkMCP.Server.facadeCount(folder))
        if turns > 0 { args += ["--max-turns", "\(turns)"] }
        if let effort = UserDefaults.standard.string(forKey: ClaudeSettings.effortKey), !effort.isEmpty {
            args += ["--effort", effort]
        }
        if request != nil, let session = LandmarkAgent.conversation(folder) {
            args += ["--resume", session]
        } else {
            let session = UUID().uuidString.lowercased()
            args += ["--session-id", session]
            let json = try? JSONSerialization.data(withJSONObject: ["session": session, "started": ISO8601DateFormatter().string(from: Date())],
                                                   options: [.prettyPrinted, .sortedKeys])
            try? json?.write(to: folder.appendingPathComponent("agent.json"))
        }
        if let request { console.append("> \(request)") }
        let p = Process()
        p.executableURL = claude
        p.arguments = args
        p.currentDirectoryURL = folder
        p.environment = ClaudeSettings.environment
        let pipe = Pipe(), errors = Pipe()
        p.standardOutput = pipe
        p.standardError = errors
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            end(.failed("cannot start claude"), "Cannot start claude: \(error.localizedDescription)")
            return
        }
        process = p
        phase = .modelling
        state = .running
        console.stage(name: "Claude is modelling \(name)")
        stateChanged()
        Task {
            // How the run ended, by Claude Code's result event: nil when the
            // stream ended without one.
            var ok: Bool?
            // Its stderr read as it comes too, so a pipe full of it never
            // stalls Claude: what it said, for the log when the run fails.
            async let saying = PipeLines.all(of: errors.fileHandleForReading)
            let raw = folder.appendingPathComponent(Self.streamName)
            if FileManager.default.createFile(atPath: raw.path, contents: nil) { stream = try? FileHandle(forWritingTo: raw) }
            for await line in PipeLines.lines(of: pipe.fileHandleForReading) {
                try? stream?.write(contentsOf: Data((line + "\n").utf8))
                if let event = LandmarkAgent.event(line) {
                    if let text = event.text { console.append(text) }
                    if event.toolDone { modelChanged() }
                    if let result = event.ok { ok = result }
                }
            }
            await Task.detached { p.waitUntilExit() }.value
            let said = await saying
            let why: String? = stopping ? nil
                : ok == nil ? "no result from claude (exit \(p.terminationStatus))"
                : ok == false ? "Claude ended with an error"
                : p.terminationStatus != 0 ? "claude exited \(p.terminationStatus)" : nil
            if let why {
                console.append("Failed: \(why).")
                if !said.isEmpty { console.append(said) }
            }
            end(stopping ? .stopped : why.map { .failed($0) } ?? .done)
        }
    }
}
