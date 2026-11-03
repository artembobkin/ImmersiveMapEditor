import Foundation

/// A file of the shared cache (the data folder's cache/: Mapillary's
/// coverage tiles, Esri's imagery tiles) fetched with curl into a part
/// file of this process's own, then renamed into place in one step. Several
/// landmarks are modelled at once (the user, 2026-11-01), so another
/// process reading or fetching the same file at the same moment sees the
/// old one or the whole new one, never half of it.
enum CacheFile {
    /// Fetches `url` into `file`; `curl` are the options before the output
    /// and the URL, `run` runs curl. The status is non-zero when the fetch
    /// or the rename failed.
    static func fetch(_ url: String, to file: URL, curl: [String], run: (URL, [String]) -> (Int32, String)) -> (Int32, String) {
        let part = file.path + ".\(getpid()).part"
        let (status, said) = run(URL(fileURLWithPath: "/usr/bin/curl"), curl + ["-o", part, url])
        if status == 0, rename(part, file.path) == 0 { return (0, said) }
        try? FileManager.default.removeItem(atPath: part)
        return (status == 0 ? 1 : status, said)
    }
}
