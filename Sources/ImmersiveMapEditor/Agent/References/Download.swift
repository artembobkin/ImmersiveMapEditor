import Foundation

/// A download of the agent's sources (Mapillary, Esri, Wikimedia Commons)
/// through URLSession, which takes the Mac's own proxy settings, its PAC
/// file included, where curl, used before, takes only the shell's
/// variables: on the user's network Mapillary's hosts, Meta's, resolve to
/// 127.0.0.1 unless asked through the proxy the system sets, so the editor
/// started from the Finder and the agent's server under Codex, both without
/// the shell's variables, were refused in a millisecond (the user,
/// 2026-11-21). No proxy is named anywhere: the system's settings decide.
///
/// Synchronous, for the tools' synchronous code, and safe from any thread.
/// Each answer is curl's in form, a status and what was said: 0 and the
/// body (or nothing, written to a file), else non-zero and why.
enum Download {
    /// What a download comes to.
    struct Answer {
        var status: Int32
        var said: String
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: configuration)
    }()

    /// The body of `url` as text; with `failing`, an HTTP error is a failure
    /// (curl's -f), else its body is the answer too (Mapillary explains an
    /// error in its JSON).
    static func text(_ url: String, timeout: TimeInterval = 60, agent: String? = nil, failing: Bool = true) -> Answer {
        let (data, answer) = get(url, timeout: timeout, agent: agent, failing: failing, maximum: nil)
        guard answer.status == 0 else { return answer }
        return Answer(status: 0, said: String(decoding: data ?? Data(), as: UTF8.self))
    }

    /// The body of `url` written to `file` whole, or nothing written: an
    /// HTTP error is a failure. Past `maximum` bytes it is refused.
    static func file(_ url: String, to file: URL, timeout: TimeInterval = 60, agent: String? = nil, maximum: Int? = nil) -> Answer {
        let (data, answer) = get(url, timeout: timeout, agent: agent, failing: true, maximum: maximum)
        guard answer.status == 0, let data else { return answer }
        do {
            try data.write(to: file, options: .atomic)
            return Answer(status: 0, said: "")
        } catch {
            return Answer(status: 23, said: "cannot write \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func get(_ url: String, timeout: TimeInterval, agent: String?, failing: Bool, maximum: Int?) -> (Data?, Answer) {
        guard let address = URL(string: url) else { return (nil, Answer(status: 3, said: "not a URL: \(url.prefix(120))")) }
        var request = URLRequest(url: address, timeoutInterval: timeout)
        if let agent { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        let task = session.dataTask(with: request) { data, response, error in
            result = (data, response, error)
            done.signal()
        }
        task.resume()
        // The request's own timeout is between bytes: the whole is held to
        // it too, as curl's --max-time.
        if done.wait(timeout: .now() + timeout + 5) == .timedOut {
            task.cancel()
            done.wait()
            return (nil, Answer(status: 28, said: "\(address.host ?? url) did not answer within \(Int(timeout)) s"))
        }
        let (data, response, error) = result
        if let error {
            let host = address.host ?? url
            let code = (error as? URLError)?.code
            return (nil, Answer(status: code == .timedOut ? 28 : 7, said: "\(host): \(error.localizedDescription)"))
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if failing, statusCode >= 400 {
            let body = String(decoding: (data ?? Data()).prefix(300), as: UTF8.self)
            return (nil, Answer(status: 22, said: "HTTP \(statusCode) from \(address.host ?? url)" + (body.isEmpty ? "" : ": \(body)")))
        }
        if let maximum, (data?.count ?? 0) > maximum {
            return (nil, Answer(status: 63, said: "larger than \(maximum / 1_000_000) MB"))
        }
        return (data, Answer(status: 0, said: ""))
    }
}
