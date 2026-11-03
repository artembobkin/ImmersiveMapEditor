import Foundation

/// The lines of a pipe as they come, read by Foundation on a thread of its
/// own as soon as they are written and kept until asked for, so the pipe is
/// never left full while the reader is away. Claude Code runs on Node,
/// which writes to a pipe without waiting and drops what is still unwritten
/// when it exits: four runs read with `FileHandle.bytes` from the main actor
/// ended "no result from claude (exit 0)" in a quarter of an hour with
/// Claude's own transcripts complete, one of them with exactly the pipe's
/// 64 KiB received (the user, 2026-11-02).
enum PipeLines {
    /// Every line of the handle, without its newline, until the writer
    /// closes its end; the last line without a newline too.
    static func lines(of handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            var rest = Data()
            // Where the search for a newline goes on: only the new bytes
            // are looked at, so a long line is not scanned again each time.
            var scanned = 0
            handle.readabilityHandler = { h in
                let data = h.availableData
                guard !data.isEmpty else {
                    h.readabilityHandler = nil
                    if !rest.isEmpty { continuation.yield(String(decoding: rest, as: UTF8.self)) }
                    continuation.finish()
                    return
                }
                rest.append(data)
                while let newline = rest[(rest.startIndex + scanned)...].firstIndex(of: 0x0A) {
                    continuation.yield(String(decoding: rest[rest.startIndex..<newline], as: UTF8.self))
                    rest.removeSubrange(rest.startIndex...newline)
                    scanned = 0
                }
                scanned = rest.count
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }

    /// Everything the handle gives until it is closed, as one string.
    static func all(of handle: FileHandle) async -> String {
        var out: [String] = []
        for await line in lines(of: handle) { out.append(line) }
        return out.joined(separator: "\n")
    }
}
