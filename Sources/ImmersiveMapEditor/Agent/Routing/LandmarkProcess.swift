import Foundation

/// A landmark's own server, the editor run as `landmark-mcp FOLDER` with
/// this process's environment: its answers read a line at a time.
final class LandmarkProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let lock = NSLock()

    var alive: Bool { process.isRunning }

    init(folder: URL, answer: @escaping ([String: Any]) -> Void, ended: @escaping () -> Void) throws {
        process.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["landmark-mcp", folder.path]
        process.standardInput = input
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        process.terminationHandler = { _ in ended() }
        try process.run()
        // Its answers, a line each, some of them megabytes of pictures.
        Thread.detachNewThread {
            let reader = output.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let end = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = buffer[buffer.startIndex..<end]
                    buffer.removeSubrange(buffer.startIndex...end)
                    if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { answer(message) }
                }
            }
        }
        send(["jsonrpc": "2.0", "id": "start", "method": "initialize",
              "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "tile", "version": "1"]]])
        send(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
        // A server that ended is written to in vain, never with a crash.
        lock.withLock { try? input.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8)) }
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }
}
