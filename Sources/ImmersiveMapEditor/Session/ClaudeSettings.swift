import Foundation
import Security

/// How the editor runs Claude Code (the `claude` command, on the user's own
/// subscription) for its agents: where `claude` is, and the proxy it must
/// go through. The proxy can hold a user name and password, so it is kept
/// in the user's keychain, never in the repository, a file of the project
/// or the defaults; the editor hands it to `claude` in its environment
/// (HTTP_PROXY, HTTPS_PROXY, ALL_PROXY, their lowercase twins, NO_PROXY), as
/// the user's ~/bin/claude launcher does.
enum ClaudeSettings {
    static let executableKey = "claude.executable"
    /// The model the agents ask for (an alias such as opus), else Claude
    /// Code's own default.
    static let modelKey = "claude.model"
    /// How hard the agents think: Claude Code's --effort (low, medium, high,
    /// xhigh, max), or its default when empty.
    static let effortKey = "claude.effort"
    /// How the agent finds the one or two things that make the building
    /// recognisable, for the generator to draw a size up (the user,
    /// 2026-10-28): "known" from what it knows of the place alone (a
    /// photo only if it wants one), "photos" from what it knows and, for a
    /// building it does not know, the roof and corners of the
    /// whole-building photo, or "off" for a plain building.
    static let emphasisKey = "landmark.emphasis"
    static var emphasis: String {
        let v = UserDefaults.standard.string(forKey: emphasisKey) ?? "photos"
        return ["off", "known", "photos"].contains(v) ? v : "photos"
    }
    /// The agent's turns for one landmark, a safety stop (Claude Code's
    /// --max-turns), per facade: the plan is a build, a build of the fixes
    /// its comparisons show, and a summary, four tool calls, each a turn or
    /// two of the model (the user, 2026-10-28). 0 for no stop.
    static let turnsPerFacadeKey = "landmark.turnsPerFacade"
    static var turnsPerFacade: Int {
        let v = UserDefaults.standard.object(forKey: turnsPerFacadeKey) as? Int
        return v ?? 3
    }
    /// The turns allowed for a landmark of `facades` facades: 3 a facade
    /// and 8 besides, so four facades get 20 (the plan takes four calls).
    static func maxTurns(facades: Int) -> Int {
        let per = turnsPerFacade
        return per <= 0 ? 0 : per * max(1, facades) + 8
    }

    /// The `claude` to run: the one picked, else the first installed.
    static var executable: URL? {
        if let path = UserDefaults.standard.string(forKey: executableKey), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// The proxy every request of `claude` goes through, and what bypasses it.
    /// While none is set, the one of the user's ~/bin/claude launcher is
    /// taken (into the keychain) the first time it is asked for.
    static var proxy: String {
        get {
            if let p = Keychain.read("claude.proxy"), !p.isEmpty { return p }
            takeProxy(fromLauncher: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin/claude"))
            return Keychain.read("claude.proxy") ?? ""
        }
        set { Keychain.write("claude.proxy", newValue) }
    }
    static var noProxy: String {
        get { Keychain.read("claude.noProxy") ?? "" }
        set { Keychain.write("claude.noProxy", newValue) }
    }

    /// Mapillary's access token (its street-level photos, CC BY-SA, are the
    /// landmarks' agent's references), in the keychain.
    static var mapillaryToken: String {
        get { Keychain.read("mapillary.token") ?? "" }
        set { Keychain.write("mapillary.token", newValue) }
    }

    /// The environment `claude` runs in: the editor's, with the proxy, and
    /// without the user's CLAUDE.md files and auto memory: the agent's
    /// context holds its job alone (the user, 2026-10-26).
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        let proxy = self.proxy, noProxy = self.noProxy
        if !proxy.isEmpty {
            for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"] {
                env[key] = proxy
                env[key.lowercased()] = proxy
            }
        }
        if !noProxy.isEmpty {
            env["NO_PROXY"] = noProxy
            env["no_proxy"] = noProxy
        }
        return env
    }

    /// Takes the proxy from a launcher script that exports it (the user's
    /// ~/bin/claude): its HTTPS_PROXY (else HTTP_PROXY, ALL_PROXY) and
    /// NO_PROXY lines. Returns whether it found a proxy. The values go to the
    /// keychain only.
    @discardableResult
    static func takeProxy(fromLauncher url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        var found: [String: String] = [:]
        for line in text.split(separator: "\n") {
            var l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("export ") else { continue }
            l.removeFirst("export ".count)
            let pair = l.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            found[pair[0]] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        guard let proxy = found["HTTPS_PROXY"] ?? found["HTTP_PROXY"] ?? found["ALL_PROXY"] ?? found["https_proxy"] else { return false }
        self.proxy = proxy
        if let no = found["NO_PROXY"] ?? found["no_proxy"] { noProxy = no }
        return true
    }
}

/// Strings of the editor's own in the user's keychain (generic passwords of
/// the service "ImmersiveMapEditor").
enum Keychain {
    private static let service = "ImmersiveMapEditor"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes a value, or removes it when empty.
    static func write(_ account: String, _ value: String) {
        let match: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(match as CFDictionary)
        guard !value.isEmpty else { return }
        var add = match
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
