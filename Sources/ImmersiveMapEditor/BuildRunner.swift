import Foundation
import Observation
import SwiftUI

/// Runs the pipeline (the `tilepipeline` program beside the editor) on the
/// workspace and keeps its output as it comes, for the Build window.
@Observable
@MainActor
final class BuildRunner {
    private(set) var log = ""
    private(set) var running = false

    func run(root: URL, arguments: [String], done: @escaping @MainActor () -> Void = {}) {
        guard !running else {
            log += "A build is running already.\n"
            return
        }
        running = true
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

/// The Build window: the pipeline's output, following its end.
struct BuildLogView: View {
    @Environment(BuildRunner.self) private var runner

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                Text(runner.log.isEmpty ? "No build yet. Tiles > Fetch and Build (⌘B)." : runner.log)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                Color.clear.frame(height: 1).id("end")
            }
            .onChange(of: runner.log) { reader.scrollTo("end", anchor: .bottom) }
        }
        .frame(minWidth: 600, minHeight: 300)
        .toolbar {
            if runner.running { ProgressView().controlSize(.small) }
        }
    }
}
