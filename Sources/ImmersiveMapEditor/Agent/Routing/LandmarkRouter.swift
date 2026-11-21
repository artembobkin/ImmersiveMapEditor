import Foundation
import TileKit

/// The landmarks' own servers behind a server over many of them (`TileMCP`,
/// `AreaMCP`): a call for a landmark goes to that landmark's server, the
/// editor run as `landmark-mcp LANDMARK_FOLDER` in a process of its own
/// (`LandmarkProcess`), started at its first call and kept, and its answer
/// comes back under the agent's id. So the subagents' builds and renders
/// run side by side, each landmark's state stays its own, and nothing of a
/// landmark's server changes.
final class LandmarkRouter: @unchecked Sendable {
    private let channel: MCPChannel
    private let lock = NSLock()
    /// The landmarks' processes by key (the landmark's folder's path).
    private var processes: [String: LandmarkProcess] = [:]
    /// The calls passed on and not answered yet: the id given to the
    /// process, to the agent's id and the process's key.
    private var pending: [Int: (id: Any, key: String)] = [:]
    private var nextId = 1

    init(channel: MCPChannel) { self.channel = channel }

    /// The tool call `name` with `args` for the landmark in `folder`, its
    /// answer given to the agent under `id` when it comes.
    func call(_ name: String, _ args: [String: Any], landmark folder: URL, id: Any) {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("landmark.json").path) else {
            channel.reply(MCPChannel.failure(id, "no landmark \(folder.lastPathComponent) there: list_landmarks names them"))
            return
        }
        do {
            let process = try self.process(folder)
            let processId: Int = lock.withLock {
                let n = nextId
                nextId += 1
                pending[n] = (id, folder.path)
                return n
            }
            process.send(["jsonrpc": "2.0", "id": processId, "method": "tools/call", "params": ["name": name, "arguments": args]])
        } catch {
            channel.reply(MCPChannel.failure(id, "the tools of \(folder.lastPathComponent) did not start: \(error)"))
        }
    }

    func quit() {
        for process in lock.withLock({ Array(processes.values) }) { process.stop() }
    }

    /// The landmark's server, started at its first call.
    private func process(_ folder: URL) throws -> LandmarkProcess {
        let key = folder.path
        return try lock.withLock {
            if let running = processes[key], running.alive { return running }
            let process = try LandmarkProcess(folder: folder,
                                              answer: { [weak self] message in self?.answer(message) },
                                              ended: { [weak self] in self?.ended(key, name: folder.lastPathComponent) })
            processes[key] = process
            return process
        }
    }

    /// A landmark's server's answer, given back under the agent's id.
    private func answer(_ message: [String: Any]) {
        guard let processId = message["id"] as? Int,
              let call = lock.withLock({ pending.removeValue(forKey: processId) }) else { return }
        var out = message
        out["id"] = call.id
        channel.reply(out)
    }

    /// A landmark's server gone: its calls still open answered with a failure.
    private func ended(_ key: String, name: String) {
        let open: [Any] = lock.withLock {
            let mine = pending.filter { $0.value.key == key }
            for k in mine.keys { pending[k] = nil }
            processes[key] = nil
            return mine.values.map(\.id)
        }
        for id in open { channel.reply(MCPChannel.failure(id, "the tools of \(name) stopped; call again")) }
    }

    // MARK: What a tile's landmarks are

    /// Every landmark of a tile's `landmarks/` folder, a line each: its id,
    /// name, how many buildings, a monument, whether it has a model.
    static func listLandmarks(in landmarks: URL) -> String {
        let folders = ((try? FileManager.default.contentsOfDirectory(at: landmarks, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("landmark.json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var lines: [String] = []
        var without = 0
        for folder in folders {
            let json = (try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("landmark.json")))) as? [String: Any] ?? [:]
            let name = json["name"] as? String ?? folder.lastPathComponent
            let buildings = (json["buildings"] as? [Any])?.count ?? 0
            let model = FileManager.default.fileExists(atPath: folder.appendingPathComponent("model.glb").path)
            // One given up on for want of references is not to be started again.
            let skipped = model ? nil : LandmarkSkip.reason(in: folder)
            if !model, skipped == nil { without += 1 }
            let monument = json["monument"] as? Bool ?? false
            lines.append("\(folder.lastPathComponent): \(name), \(buildings) building\(buildings == 1 ? "" : "s")"
                         + (monument ? ", a monument" : "") + (model ? ", has a model" : skipped.map { ", skipped before (\($0)): leave it" } ?? ", NO MODEL"))
        }
        return "\(folders.count) landmarks, \(without) to model, marked NO MODEL (id: name):\n" + lines.joined(separator: "\n")
    }

    /// A landmark's whole brief, as Copy Prompt gives it, with how its
    /// tools are called here (`calling`).
    static func brief(_ folder: URL, calling: String) throws -> String {
        guard let source = try? LandmarkSource(folder.appendingPathComponent("landmark.json")) else {
            throw MCPChannel.Failure("no landmark \(folder.lastPathComponent) there: list_landmarks names them")
        }
        return LandmarkAgent.prompt(source.name, monument: source.isMonument, fine: LandmarkMCP.Server.fine) + "\n\n" + calling
    }

    /// Whether a name given for a folder is one: no path, nothing hidden.
    static func isName(_ s: String) -> Bool { !s.isEmpty && !s.contains("/") && !s.hasPrefix(".") }
}
