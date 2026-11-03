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
    /// The log as lines, what the bottom panel shows (a row each, laid out
    /// only where in view: one text of the whole log, selectable, was laid
    /// out again at every change of the panel's size; the user, 2026-11-03).
    private(set) var lines: [String] = []
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
        lines = title.isEmpty ? [] : [title]
        running = true
        stage = name.map { Stage(name: $0) }
        step = (0, 0)
        #if DEBUG
        // Every job runs the editor's own binary (the pipeline, Claude's
        // tools), and a Debug one is tens of times slower (the user,
        // 2026-11-03: a landmark modelled in 5 minutes instead of 2;
        // GUM's set_recipe took 322 s in Debug and 8 s in Release).
        append("The editor runs in Debug: its builds and Claude's tools run tens of times slower than in Release. Run the Release scheme.")
        #endif
    }

    func append(_ text: String) {
        let whole = text.hasSuffix("\n") ? text : text + "\n"
        log += whole
        lines += whole.dropLast().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// What the job is doing now, said by the job itself.
    func stage(name: String) { stage = Stage(name: name) }

    func stage(_ next: Stage?) { stage = next }

    func step(_ index: Int, of count: Int) { step = (index, count) }

    func end(_ ok: Bool) {
        stage = nil
        log += "\n" + (ok ? "Done." : "Stopped.") + "\n"
        lines += ["", ok ? "Done." : "Stopped."]
        running = false
    }

    /// A stage from the JSON of a pipeline's `@progress` line.
    static func stage(progress json: Substring) -> Stage? {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let name = o["stage"] as? String else { return nil }
        return Stage(name: name, fraction: (o["fraction"] as? NSNumber)?.doubleValue, detail: o["detail"] as? String)
    }
}
