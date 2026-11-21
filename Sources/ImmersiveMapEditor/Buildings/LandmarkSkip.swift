import Foundation

/// A landmark the agent gave up on, with why: no reference photo of it was
/// found within the search's budget, so nothing was built (the user,
/// 2026-11-21: no model without references, and the building shown red so
/// it is seen that one was tried). Kept as `skipped.json` in the landmark's
/// folder by the agent's skip_landmark; gone once a model is built, or
/// with Forget Agent's Work.
enum LandmarkSkip {
    static let file = "skipped.json"

    /// Why the landmark in `folder` was skipped; nil when it was not.
    static func reason(in folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(file)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["reason"] as? String ?? "no references"
    }

    /// When it was skipped, for noticing a change of it.
    static func date(in folder: URL) -> Date? {
        try? folder.appendingPathComponent(file).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func write(_ reason: String, in folder: URL) throws {
        let json: [String: Any] = ["reason": reason, "when": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent(file), options: .atomic)
    }

    static func clear(in folder: URL) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
    }
}
