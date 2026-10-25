import Foundation

/// The pipeline's progress, for whoever runs it: a line on stdout,
///
///   @progress {"stage":"Fetching OSM","fraction":0.42,"detail":"3.4 MB, 1.1 MB/s"}
///
/// which a terminal shows as it is and the editor reads into its progress
/// bar instead of its log. `fraction` (0...1) is left out while the end is
/// not known. Reports of one stage come at most ten a second, its end
/// always. Safe from any thread.
public enum Progress {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var last = (stage: "", time: 0.0)

    public static func report(_ stage: String, fraction: Double? = nil, detail: String? = nil) {
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock()
        defer { lock.unlock() }
        if stage == last.stage, now - last.time < 0.1, (fraction ?? 0) < 1 { return }
        last = (stage, now)
        var line: [String: Any] = ["stage": stage]
        if let fraction { line["fraction"] = (min(1, max(0, fraction)) * 1000).rounded() / 1000 }
        if let detail { line["detail"] = detail }
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        print("@progress " + json)
    }

    /// Bytes as people read them: 812 KB, 3.4 MB.
    public static func bytes(_ n: Int) -> String {
        n < 1_000_000 ? String(format: "%.0f KB", Double(n) / 1000) : String(format: "%.1f MB", Double(n) / 1_000_000)
    }
}
