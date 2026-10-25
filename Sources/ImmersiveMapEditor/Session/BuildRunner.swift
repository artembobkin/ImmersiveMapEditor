import Foundation
import Observation

/// Runs the pipeline (the editor itself, as `ImmersiveMapEditor pipeline`,
/// TileKit's PipelineCommand: the same build, never older) on the
/// workspace and keeps its output as it comes, for the log at the foot of
/// the window.
@Observable
@MainActor
final class BuildRunner {
    private(set) var log = ""
    private(set) var running = false
    /// What the pipeline is doing now, from its `@progress` lines (TileKit's
    /// `Progress`): the stage, how far it is when that is known, a detail.
    struct Stage: Equatable {
        var name: String
        var fraction: Double?
        var detail: String?
    }
    private(set) var stage: Stage?
    /// Which command of a run this is, and how many there are.
    private(set) var step = (index: 0, count: 0)

    func run(root: URL, arguments: [String], done: @escaping @MainActor (Bool) -> Void = { _ in }) {
        run(root: root, steps: [arguments], done: done)
    }

    /// Runs the pipeline's commands one after another, stopping at the first
    /// that fails, then `done` with whether all of them went through.
    func run(root: URL, steps: [[String]], done: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !running else {
            log += "A build is running already.\n"
            return
        }
        log = ""
        running = true
        stage = nil
        Task {
            var ok = true
            for (i, arguments) in steps.enumerated() where ok {
                step = (i + 1, steps.count)
                ok = await run(root: root, arguments)
            }
            stage = nil
            log += "\n" + (ok ? "Done." : "Stopped.") + "\n"
            running = false
            done(ok)
        }
    }

    /// One command, its output into the log as it comes, its progress lines
    /// into `stage`.
    private func run(root: URL, _ arguments: [String]) async -> Bool {
        log += "$ tilepipeline \(arguments.joined(separator: " "))\n"
        // The editor itself, as the pipeline: one build of both.
        let tool = Bundle.main.executableURL!
        let process = Process()
        process.executableURL = tool
        process.arguments = ["pipeline", "--root", root.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            for try await line in pipe.fileHandleForReading.bytes.lines {
                if line.hasPrefix("@progress "), let s = Self.stage(line.dropFirst(10)) {
                    stage = s
                } else {
                    log += line + "\n"
                }
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 { log += "Failed (\(process.terminationStatus)).\n" }
            return process.terminationStatus == 0
        } catch {
            log += "Cannot start \(tool.path): \(error.localizedDescription)\n"
            return false
        }
    }

    private static func stage(_ json: Substring) -> Stage? {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let name = o["stage"] as? String else { return nil }
        return Stage(name: name, fraction: (o["fraction"] as? NSNumber)?.doubleValue, detail: o["detail"] as? String)
    }
}
