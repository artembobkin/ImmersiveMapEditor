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

    func run(root: URL, arguments: [String], done: @escaping @MainActor () -> Void = {}) {
        guard !running else {
            log += "A build is running already.\n"
            return
        }
        running = true
        shown = true
        log = "$ tilepipeline \(arguments.joined(separator: " "))\n"
        // Built with the editor, in the same folder (or the app's MacOS folder).
        let tool = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("tilepipeline")
        let process = Process()
        process.executableURL = tool
        process.arguments = ["--root", root.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        Task {
            do {
                try process.run()
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    log += line + "\n"
                }
                process.waitUntilExit()
                log += "\n" + (process.terminationStatus == 0 ? "Done." : "Failed (\(process.terminationStatus)).")
                    + " The 3D view shows the new tiles.\n"
            } catch {
                log += "Cannot start \(tool.path): \(error.localizedDescription)\n"
            }
            running = false
            done()
        }
    }
}
