import Foundation

/// The JSON-RPC of an MCP server on stdio, as the servers over many
/// landmarks speak it (`TileMCP`, `AreaMCP`): the messages read a line at a
/// time, every answer written whole as one line under a lock (the answers
/// of the landmarks' processes come from their own threads), and the
/// shapes of an answer.
final class MCPChannel: @unchecked Sendable {
    private let lock = NSLock()

    /// Reads the agent's messages until its input ends, each handed to `handle`.
    func serve(_ handle: ([String: Any]) -> Void) {
        // A landmark's process that ended takes no signal down with it.
        signal(SIGPIPE, SIG_IGN)
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            handle(message)
        }
    }

    func reply(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
        lock.withLock { try? FileHandle.standardOutput.write(contentsOf: data + Data("\n".utf8)) }
    }

    /// The answer to a request the server answers itself that is not a tool
    /// call: initialize, ping, tools/list; nil for a tool call, and an
    /// error for any other method.
    func answerProtocol(_ m: [String: Any], tools: [[String: Any]]) -> Bool {
        guard let id = m["id"] else { return true }
        let params = m["params"] as? [String: Any] ?? [:]
        switch m["method"] as? String ?? "" {
        case "initialize":
            reply(Self.ok(id, ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                               "capabilities": ["tools": [:]],
                               "serverInfo": ["name": "landmark", "version": "1"]]))
        case "ping":
            reply(Self.ok(id, [:]))
        case "tools/list":
            reply(Self.ok(id, ["tools": tools]))
        case "tools/call":
            return false
        default:
            reply(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "no method \(m["method"] ?? "")"]])
        }
        return true
    }

    static func ok(_ id: Any, _ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
    static func result(_ id: Any, _ content: [[String: Any]]) -> [String: Any] { ok(id, ["content": content, "isError": false]) }
    static func failure(_ id: Any, _ why: String) -> [String: Any] { ok(id, ["content": [text(why)], "isError": true]) }
    static func text(_ s: String) -> [String: Any] { ["type": "text", "text": s] }

    /// Tools each given more arguments, required: a landmark's tools as a
    /// server over many landmarks offers them.
    static func adding(_ arguments: [(name: String, schema: [String: Any])], to tools: [[String: Any]]) -> [[String: Any]] {
        tools.map { tool in
            var tool = tool
            var schema = tool["inputSchema"] as? [String: Any] ?? ["type": "object"]
            var properties = schema["properties"] as? [String: Any] ?? [:]
            for a in arguments { properties[a.name] = a.schema }
            schema["properties"] = properties
            schema["required"] = arguments.map(\.name) + (schema["required"] as? [String] ?? [])
            tool["inputSchema"] = schema
            return tool
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }
}
