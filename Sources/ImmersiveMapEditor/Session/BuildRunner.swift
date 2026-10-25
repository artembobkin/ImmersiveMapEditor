import Foundation
import Observation

/// Runs the pipeline (the `tilepipeline` program beside the editor) on the
/// workspace and keeps its output as it comes, for the log at the foot of
/// the window.
@Observable
@MainActor
final class BuildRunner {
    private(set) var log = ""
    private(set) var running = false
    /// Whether the log is open at the foot of the window: a build opens it.
    var shown = false

    /// The last line the pipeline wrote, for the status line.
    var lastLine: String {
        log.split(separator: "\n").last.map(String.init) ?? ""
    }

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
        running = true
        shown = true
        log = ""
        Task {
            var ok = true
            for arguments in steps where ok {
                ok = await step(root: root, arguments)
            }
            log += "\n" + (ok ? "Done." : "Stopped.") + "\n"
            running = false
            done(ok)
        }
    }

    /// One command, its output into the log as it comes.
    private func step(root: URL, _ arguments: [String]) async -> Bool {
        log += "$ tilepipeline \(arguments.joined(separator: " "))\n"
        // Built with the editor, in the same folder (or the app's MacOS folder).
        let tool = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("tilepipeline")
        let process = Process()
        process.executableURL = tool
        process.arguments = ["--root", root.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            for try await line in pipe.fileHandleForReading.bytes.lines {
                log += line + "\n"
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 { log += "Failed (\(process.terminationStatus)).\n" }
            return process.terminationStatus == 0
        } catch {
            log += "Cannot start \(tool.path): \(error.localizedDescription)\n"
            return false
        }
    }
}
