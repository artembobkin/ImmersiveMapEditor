import Foundation

/// A file of the shared cache (the data folder's cache/: Mapillary's
/// coverage tiles, Esri's imagery tiles) fetched (`Download`) into a part
/// file of this process's own, then renamed into place in one step. Several
/// landmarks are modelled at once (the user, 2026-11-01), so another
/// process reading or fetching the same file at the same moment sees the
/// old one or the whole new one, never half of it.
enum CacheFile {
    /// Fetches `url` into `file`, waiting `timeout` seconds at most. The
    /// status is non-zero when the fetch or the rename failed.
    static func fetch(_ url: String, to file: URL, timeout: TimeInterval) -> (Int32, String) {
        let part = file.path + ".\(getpid()).part"
        let answer = Download.file(url, to: URL(fileURLWithPath: part), timeout: timeout)
        let (status, said) = (answer.status, answer.said)
        if status == 0, rename(part, file.path) == 0 { return (0, said) }
        try? FileManager.default.removeItem(atPath: part)
        return (status == 0 ? 1 : status, said)
    }
}
