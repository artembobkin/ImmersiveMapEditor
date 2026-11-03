import Foundation
import Observation

/// The log of one job (`Job`), shown at the foot of the window while the
/// job's subject is what the window is about: its lines as they come, what
/// the job is doing now (`stage`: the pipeline's `@progress` lines, TileKit's
/// `Progress`, or said by the job itself), and which of its commands this
/// is. A job writes it, the bottom panel and the status line read it.
@Observable
@MainActor
final class Console {
    private(set) var log = ""
    private(set) var running = false
    /// The stage, how far it is when that is known, a detail.
    struct Stage: Equatable {
        var name: String
        var fraction: Double?
        var detail: String?
    }
    private(set) var stage: Stage?
    /// Which command of the job this is, and how many there are.
    private(set) var step = (index: 0, count: 0)

    /// The log started over with the job's title, the job running.
    func begin(_ title: String, stage name: String? = nil) {
        log = title.isEmpty ? "" : title + "\n"
        running = true
        stage = name.map { Stage(name: $0) }
        step = (0, 0)
    }

    func append(_ text: String) { log += text.hasSuffix("\n") ? text : text + "\n" }

    /// What the job is doing now, said by the job itself.
    func stage(name: String) { stage = Stage(name: name) }

    func stage(_ next: Stage?) { stage = next }

    func step(_ index: Int, of count: Int) { step = (index, count) }

    func end(_ ok: Bool) {
        stage = nil
        log += "\n" + (ok ? "Done." : "Stopped.") + "\n"
        running = false
    }

    /// A stage from the JSON of a pipeline's `@progress` line.
    static func stage(progress json: Substring) -> Stage? {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let name = o["stage"] as? String else { return nil }
        return Stage(name: name, fraction: (o["fraction"] as? NSNumber)?.doubleValue, detail: o["detail"] as? String)
    }
}
