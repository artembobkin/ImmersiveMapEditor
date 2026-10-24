import AppKit

/// Runs the pipeline (pipeline.py) in the project's folder and shows its
/// output as it comes, so a correction can be seen in the built tiles.
final class BuildRunner {
    let window: NSWindow
    private let text: NSTextView
    private var process: Process?

    init() {
        let scroll = NSTextView.scrollableTextView()
        text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
                          styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "Build"
        window.contentView = scroll
        window.isReleasedWhenClosed = false
        window.center()
    }

    func run(root: URL, arguments: [String], done: @escaping () -> Void = {}) {
        window.makeKeyAndOrderFront(nil)
        if let process, process.isRunning {
            append("A build is running already.\n")
            return
        }
        text.string = ""
        let p = Process()
        // Homebrew's or the system's: the pipeline needs only the standard library.
        let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = ["-u"] + arguments
        p.currentDirectoryURL = root
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.append(s) }
        }
        p.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.append("\n" + (p.terminationStatus == 0 ? "Done." : "Failed (\(p.terminationStatus)).") +
                             " The 3D view shows the new tiles.\n")
                done()
            }
        }
        append("$ \(python) \(arguments.joined(separator: " "))\n")
        do {
            try p.run()
            process = p
        } catch {
            append("Cannot start: \(error.localizedDescription)\n")
        }
    }

    private func append(_ s: String) {
        text.textStorage?.append(NSAttributedString(string: s, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.textColor]))
        text.scrollToEndOfDocument(nil)
    }
}
